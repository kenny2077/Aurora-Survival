# Camera Capture and Attachment Decision

Date: 2026-08-21

## Decision

The Ask composer's Add control presents a source choice before requesting any
permission. Choosing an existing photo requests Photo Library `.readWrite`
authorization when needed and preserves iOS limited/full/deny behavior. Choosing
Take Photo requests Camera authorization and presents the standard
`UIImagePickerController` still-camera interface.

A camera capture is not an attachment until it has been saved successfully to the
user's Photo Library. After capture, Aurora requests or checks Photo Library
access, saves one user-initiated image, and only then passes those bytes through the
existing bounded attachment pipeline. Album denial, restriction, or save failure
discards the temporary capture and creates no new attachment.

Cancellation and failed replacement preserve the prior attachment. Errors are
separate composer state so a stale failed object is never presented as ready.
Temporary full-size capture bytes are released after save-and-prepare or failure;
only the bounded draft and existing transcript thumbnail lifecycle remain.

Aurora never enumerates albums, retains a PhotoKit asset identifier, scans in
the background, or introduces a custom capture session. Camera authorization and
capture saving are injectable internal services; public chat, model, package,
transcript, Expert vision, and Lite interfaces are unchanged.

## Decision log

- Request permissions after source choice to avoid unnecessary Camera or Photo
  Library prompts.
- Use the Apple system camera rather than a custom AVFoundation session.
- Require successful album saving before attachment; failed saves are discarded.
- Preserve prior draft state across cancellation and replacement failure.
- Limit physical verification to camera success, existing selection, and forced
  save failure.

