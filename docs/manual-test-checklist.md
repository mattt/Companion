# Manual test checklist

Run through this list on macOS before a release.
It covers the flows that unit tests cannot reach.
Record the macOS and Xcode versions with the results.

## Setup

- [ ] Build and run the `Companion` scheme.
- [ ] Confirm that the welcome screen appears when no servers are saved.

## Add and connect

- [ ] Click "Add Example Server".
  The "Everything" server appears in the sidebar and connects.
- [ ] Confirm that the server shows its name, version, protocol version,
  and capabilities on the server detail screen.
- [ ] Confirm that prompts, resources, and tools appear in the sidebar
  with correct counts.

## Tools, prompts, and resources

- [ ] Open a tool, fill in its arguments, and call it.
  Confirm that the result appears.
- [ ] Open a second tool and confirm that the first tool's input
  does not carry over.
  Return to the first tool and confirm that its input is still there.
- [ ] Open a prompt, fill in its arguments, and submit it.
  Confirm that the prompt messages appear.
- [ ] Open a resource and read it.
  Confirm that its content appears.
- [ ] Open a resource template, fill in its parameters, and submit it.
  Confirm that the resolved URI and content appear.

## Edit and remove

- [ ] Edit the server and change its name.
  Confirm that the sidebar shows the new name.
- [ ] Use "Test Connection" in the edit sheet with the current values.
  Confirm that it succeeds.
  Change the command to an invalid value and test again.
  Confirm that it fails with an error message.
- [ ] Add a second server.
  Disconnect one server and confirm that the other stays connected.
- [ ] Remove one server.
  Confirm that it disappears and the other server is unaffected.

## Relaunch

- [ ] Quit and relaunch the app.
  Confirm that the remaining server is restored from `servers.json`
  in Application Support.
- [ ] Connect again and confirm that tools load.

## Protocol features

- [ ] On the server detail screen, click "Ping".
  Confirm that it reports the server as reachable.
- [ ] Call the `trigger-long-running-operation` tool.
  Confirm that progress appears while it runs.
  Call it again and click "Cancel".
  Confirm that the call stops.
- [ ] Call the `get-structured-content` tool for New York.
  Confirm that a Structured Content section appears
  and that the tool detail shows an Output Schema section.
- [ ] In the Server Log section, change the logging level.
  Call `toggle-simulated-logging`.
  Confirm that log messages appear, then toggle logging off.
- [ ] Call `trigger-sampling-request`.
  Confirm that a Sampling Request sheet appears.
  Generate a response, send it,
  and confirm that the tool result contains the generated text.
- [ ] Call `trigger-elicitation-request`.
  Confirm that a form appears, submit it,
  and confirm that the tool result reports your input.
- [ ] In Settings, confirm that the sampling provider and model
  match what you expect.
  If you use an API key, confirm that sampling still works
  after you quit and relaunch the app.

## Roots, headers, and authentication

- [ ] Edit the server and add a root folder.
  Call `get-roots-list`.
  Confirm that the result contains the folder you added.
- [ ] Add an environment variable in the edit sheet.
  Reconnect and call `get-env`.
  Confirm that the variable appears.
- [ ] Add a second server over HTTP
  (`npx @modelcontextprotocol/server-everything streamableHttp`,
  URL `http://127.0.0.1:3001/mcp`).
  Add a custom header and confirm that the server still connects.
- [ ] Subscribe to a resource that supports subscriptions.
  Call `toggle-subscriber-updates`.
  Confirm that the resource shows an update notice.

## Other platforms

- [ ] Build for iOS Simulator and visionOS Simulator.
- [ ] On iOS, add a remote (HTTP) server and connect to it.
