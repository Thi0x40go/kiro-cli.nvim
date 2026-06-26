#!/usr/bin/env node

/**
 * Kiro Hook Approval Client
 * Standalone, zero-dependency Node.js script.
 * Communicates tool execution requests to Neovim over TCP/Unix sockets.
 */

const net = require('net');
const fs = require('fs');
const readline = require('readline');

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
    process.exit(2); // Fail closed on parse error
  }

  // Resolve socket path or TCP port
  let target = process.env.KIRO_SOCKET_PATH;
  // If target is set from env but does not exist, check fallback paths
  if (target && !target.includes(':') && !fs.existsSync(target)) {
    target = null;
  }
  if (!target) {
    if (fs.existsSync('/tmp/kiro_bridge.sock')) {
      target = '/tmp/kiro_bridge.sock';
    } else {
      const uid = process.getuid ? process.getuid() : '1000';
      const runPath = `/run/user/${uid}/nvim/kiro_bridge.sock`;
      if (fs.existsSync(runPath)) {
        target = runPath;
      } else {
        // Default to TCP port on localhost (Windows compatibility)
        target = '127.0.0.1:49999';
      }
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
      
      if (payload.hook_event_name === 'stop') {
        if (response.block_decision) {
          process.stdout.write(JSON.stringify(response.block_decision) + '\n');
        }
        process.exit(0);
      }
      
      if (payload.hook_event_name === 'preToolUse' || !payload.hook_event_name) {
        if (response.approved) {
          process.exit(0); // 0 = Approve execution
        } else {
          console.error('\n[Security Gate] Tool execution rejected by user in Neovim.');
          process.exit(2); // 2 = Explicitly deny tool execution in Kiro
        }
      } else {
        // For agentSpawn, postToolUse, userPromptSubmit, etc.
        process.exit(0);
      }
    } catch (err) {
      console.error('[Kiro Hook] Failed to parse Neovim response:', err.message);
      // For preToolUse fail closed, for others fail open
      if (payload.hook_event_name === 'preToolUse') {
        process.exit(2);
      }
      process.exit(0);
    }
  });

  client.on('error', (err) => {
    // Log error to /tmp/kiro_hook_error.log for user diagnostics
    try {
      const logMsg = `[${new Date().toISOString()}] Target: ${target}\nError: ${err.message}\nStack: ${err.stack}\n\n`;
      fs.appendFileSync('/tmp/kiro_hook_error.log', logMsg);
    } catch (e) {}

    // If Neovim is not running, fallback behavior depends on the hook type
    if (payload.hook_event_name && payload.hook_event_name !== 'preToolUse') {
      // Non-blocking hooks can safely bypass if Neovim is down
      process.exit(0);
    }

    const toolName = payload.tool_name || payload.tool || "unknown";
    const toolInput = payload.tool_input || payload.arguments || {};

    let ttyInput, ttyOutput;
    try {
      const isWindows = process.platform === 'win32';
      const ttyDevice = isWindows ? 'CON' : '/dev/tty';
      ttyInput = fs.createReadStream(ttyDevice);
      ttyOutput = fs.createWriteStream(ttyDevice);
    } catch (e) {
      console.error(`\n[Security Gate Error] Could not connect to Neovim at ${target}:`, err.message);
      console.error('Non-interactive environment detected. Cannot prompt user. Blocked (fail-closed).');
      process.exit(2);
    }

    const rl = readline.createInterface({
      input: ttyInput,
      output: ttyOutput
    });

    ttyOutput.write(`\n==================================================`);
    ttyOutput.write(`\n[SECURITY PENDING APPROVAL - OUTSIDE NEOVIM]`);
    ttyOutput.write(`\nTool:  ${toolName}`);
    ttyOutput.write(`\nInput: ${JSON.stringify(toolInput, null, 2)}`);
    ttyOutput.write(`\n==================================================\n`);

    rl.question('Approve this tool execution? (y/N): ', (answer) => {
      rl.close();
      ttyInput.destroy();
      ttyOutput.destroy();
      const approved = answer.trim().toLowerCase() === 'y' || answer.trim().toLowerCase() === 'yes';
      if (approved) {
        process.exit(0); // 0 = Approve execution
      } else {
        console.error('\n[Security Gate] Tool execution rejected by user.');
        process.exit(2); // 2 = Explicitly deny tool execution
      }
    });
  });
});
