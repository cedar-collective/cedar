(function() {
  var OVERLAY_ID = "cedar-shiny-disconnect-overlay";
  var RETRY_SECONDS = 10;
  var retryTimer = null;

  function scheduleReload() {
    if (retryTimer) {
      return;
    }

    retryTimer = window.setInterval(function() {
      window.location.reload();
    }, RETRY_SECONDS * 1000);
  }

  function clearReload() {
    if (retryTimer) {
      window.clearInterval(retryTimer);
      retryTimer = null;
    }
  }

  function showDisconnectOverlay() {
    document.body.classList.add("cedar-shiny-disconnected");
    scheduleReload();

    if (document.getElementById(OVERLAY_ID)) {
      return;
    }

    var overlay = document.createElement("div");
    overlay.id = OVERLAY_ID;
    overlay.className = "cedar-disconnect-overlay";
    overlay.setAttribute("role", "status");
    overlay.setAttribute("aria-live", "polite");

    var panel = document.createElement("div");
    panel.className = "cedar-disconnect-panel";

    var eyebrow = document.createElement("p");
    eyebrow.className = "cedar-disconnect-eyebrow";
    eyebrow.textContent = "CEDAR update in progress";

    var heading = document.createElement("h1");
    heading.textContent = "CEDAR is restarting after an important update.";

    var message = document.createElement("p");
    message.textContent = "It should be running again in the next minute or so. This page will keep checking automatically.";

    var status = document.createElement("div");
    status.className = "cedar-disconnect-status";

    var spinner = document.createElement("span");
    spinner.className = "cedar-disconnect-spinner";
    spinner.setAttribute("aria-hidden", "true");

    var statusText = document.createElement("span");
    statusText.textContent = "Trying again every " + RETRY_SECONDS + " seconds";

    var button = document.createElement("button");
    button.className = "cedar-disconnect-button";
    button.type = "button";
    button.textContent = "Try CEDAR now";
    button.addEventListener("click", function() {
      window.location.reload();
    });

    status.appendChild(spinner);
    status.appendChild(statusText);
    panel.appendChild(eyebrow);
    panel.appendChild(heading);
    panel.appendChild(message);
    panel.appendChild(status);
    panel.appendChild(button);
    overlay.appendChild(panel);
    document.body.appendChild(overlay);
  }

  function hideDisconnectOverlay() {
    clearReload();
    document.body.classList.remove("cedar-shiny-disconnected");

    var overlay = document.getElementById(OVERLAY_ID);
    if (overlay) {
      overlay.remove();
    }
  }

  document.addEventListener("shiny:disconnected", showDisconnectOverlay);
  document.addEventListener("shiny:connected", hideDisconnectOverlay);

  if (window.jQuery) {
    window.jQuery(document).on("shiny:disconnected", showDisconnectOverlay);
    window.jQuery(document).on("shiny:connected", hideDisconnectOverlay);
  }
})();
