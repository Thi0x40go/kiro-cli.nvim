#!/usr/bin/env node

/**
 * Kiro Hook Approval Client
 * Standalone, zero-dependency Node.js script.
 * Communicates tool execution requests to Neovim over TCP/Unix sockets.
 */

const net = require('net');
const fs = require('fs');

// Read payload from Kiro CLI via STDIN
let stdinData = '';
process.stdin.setEncoding('utf8');

process.stdin.on('data', (chunk) => {
  stdinData += chunk;
});

process.stdin.on('end', () => {
  if (!stdinData.trim()) {
    process.exit(0);
  }

  let payload;
  try {
    payload = JSON.parse(stdinData);
  } catch (err) {
    console.error('[Kiro Hook] Failed to parse STDIN JSON:', err.message);
    process.exit(0); // Graceful fallback
  }

  // Resolve socket path or TCP port
  let target = process.env.KIRO_SOCKET_PATH;
  if (!target) {
    // Detect standard OS temporary path for Neovim sockets
    const uid = process.getuid ? process.getuid() : '1000';
    const runPath = `/run/user/${uid}/nvim/kiro_bridge.sock`;
    
    if (fs.existsSync(runPath)) {
      target = runPath;
    } else if (fs.existsSync('/tmp/kiro_bridge.sock')) {
      target = '/tmp/kiro_bridge.sock';
    } else {
      // Default to TCP port on localhost (Windows compatibility)
      target = '127.0.0.1:49999';
    }
  }

  let client;
  const isTCP = target.includes(':') || /^\d+$/.test(target);

  if (isTCP) {
    let host = '127.0.0.1';
    let port = 49999;
    if (target.includes(':')) {
      const parts = target.split(':');
      host = parts[0];
      port = parseInt(parts[1], 10);
    } else {
      port = parseInt(target, 10);
    }
    client = net.createConnection({ host, port });
  } else {
    client = net.createConnection({ path: target });
  }

  client.on('connect', () => {
    // Send hook payload to Neovim, delimited by newline
    client.write(JSON.stringify(payload) + '\n');
  });

  let responseData = '';
  client.on('data', (chunk) => {
    responseData += chunk.toString();
    if (responseData.includes('\n')) {
      client.end();
    }
  });

  client.on('end', () => {
    try {
      const response = JSON.parse(responseData.trim());
      if (response.approved) {
        process.exit(0); // 0 = Approve execution
      } else {
        console.error('\n[Security Gate] Tool execution rejected by user in Neovim.');
        process.exit(2); // 2 = Explicitly deny tool execution in Kiro
      }
    } catch (err) {
      console.error('[Kiro Hook] Failed to parse Neovim response:', err.message);
      process.exit(0); // Graceful fallback
    }
  });

  client.on('error', (err) => {
    // If Neovim is not running, allow execution and exit gracefully
    console.warn(`[Kiro Hook Warning] Could not connect to Neovim at ${target}:`, err.message);
    console.warn('Running outside Neovim context. Proceeding with execution.');
    process.exit(0);
  });
});
