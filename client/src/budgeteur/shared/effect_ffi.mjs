export function loadFromStore(key) {
  const value = window.localStorage.getItem(key);
  return value ?? "";
}

export function saveToStore(key, value) {
  window.localStorage.setItem(key, value);
}

export function redirect(url) {
  window.location.assign(url);
}

export function initRouting(handler) {
  const notify = () => {
    handler(window.location.pathname + window.location.search + window.location.hash);
  };

  notify();

  window.addEventListener("popstate", (event) => {
    event.preventDefault();
    notify();
  });

  document.addEventListener("click", (event) => {
    const a = event.target.closest("a");
    if (!a?.href) return;
    if (!URL.canParse(a.href)) return;
    if (a.hasAttribute("download")) return;

    const url = new URL(a.href);
    if (url.origin !== window.location.origin) return;
    if (event.ctrlKey || event.metaKey || event.altKey || event.shiftKey) return;
    if (a.target === "_blank") return;

    event.preventDefault();
    history.pushState(null, "", url.pathname + url.search + url.hash);
    notify();

    // The browser normally scrolls on navigation — since we preventDefault,
    // handle it ourselves.
    window.requestAnimationFrame(() => {
      if (url.hash) {
        document.getElementById(url.hash.slice(1))?.scrollIntoView();
      } else {
        window.scrollTo(0, 0);
      }
    });
  });
}

export function pushUrl(url) {
  history.pushState(null, "", url);
}

export function replaceUrl(url) {
  history.replaceState(null, "", url);
}

export function setTitle(title) {
  document.title = title;
}

export function getOrigin() {
  return globalThis.location.origin;
}

export function showDialog(selector) {
  const dialog = document.querySelector(selector);

  if (dialog) {
    dialog.showModal();
  } else {
    console.warn(`showDialog: Could not find element ${selector}`);
  }
}

export function closeDialog(selector) {
  const dialog = document.querySelector(selector);

  if (dialog) {
    dialog.close();
  } else {
    console.warn(`closeDialog: Could not find element ${selector}`);
  }
}

// Return a copy of `request` that aborts once `timeoutMs` elapse. gleam_fetch
// has no abort API, so the signal must be attached here. The request body is
// consumed by the original fetch call only, and cloning a Request whose body
// is a string re-creates its stream, so the clone is still sendable.
// On abort the fetch rejects with a browser-provided TimeoutError DOMException.
export function withTimeoutSignal(request, timeoutMs) {
  return new Request(request, { signal: AbortSignal.timeout(timeoutMs) });
}
