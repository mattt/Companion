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

## Other platforms

- [ ] Build for iOS Simulator and visionOS Simulator.
- [ ] On iOS, add a remote (HTTP) server and connect to it.
