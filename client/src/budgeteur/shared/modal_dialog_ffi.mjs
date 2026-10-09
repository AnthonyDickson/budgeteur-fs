// The `<modal-dialog>` custom element behind `modal_ui.dialog`. It wraps a
// `<dialog>` and opens it as a modal (`showModal`) as soon as it is inserted
// into the document, so a dialog is open exactly while the view renders it:
// removing the element closes the dialog.
//
// When the browser closes the dialog itself (Escape, or an outside click with
// `closedby="any"`), the element dispatches a `dismiss` event so the model can
// hide the modal. A dialog with `closedby="none"` (a request is in flight)
// cancels Escape, for browsers that do not support `closedby`.
export function registerModalDialog() {
  if (customElements.get("modal-dialog")) {
    return;
  }

  customElements.define(
    "modal-dialog",
    class extends HTMLElement {
      #listening = false;

      connectedCallback() {
        const dialog = this.querySelector(":scope > dialog");

        if (!dialog) {
          console.warn("modal-dialog: Could not find a child <dialog>");
          return;
        }

        // `connectedCallback` runs again if the element is moved.
        if (!this.#listening) {
          this.#listening = true;
          dialog.addEventListener("cancel", (event) => {
            if (dialog.getAttribute("closedby") === "none") {
              event.preventDefault();
            }
          });
          // Only a close by the browser reaches here while connected: the
          // model closes the dialog by removing this element.
          dialog.addEventListener("close", () => {
            if (this.isConnected) {
              this.dispatchEvent(new Event("dismiss"));
            }
          });
        }

        if (!dialog.open) {
          dialog.showModal();
        }
      }
    },
  );
}
