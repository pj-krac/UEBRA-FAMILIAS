self.addEventListener("push", event => {
  let data = {};

  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = {
      title: "UEBRA Familias",
      body: event.data
        ? event.data.text()
        : "Tiene una nueva notificación."
    };
  }

  const title = data.title || "UEBRA Familias";

  const options = {
    body: data.body || "Tiene una nueva notificación.",
    icon: "NEW%20LOGO.png",
    badge: "NEW%20LOGO.png",
    data: {
      url: data.url || "./"
    },
    tag: data.tag || "uebra-familias",
    renotify: true
  };

  event.waitUntil(
    self.registration.showNotification(title, options)
  );
});

self.addEventListener("notificationclick", event => {
  event.notification.close();

  const target = new URL(
    event.notification.data?.url || "./",
    self.location.origin
  ).href;

  event.waitUntil(
    clients
      .matchAll({
        type: "window",
        includeUncontrolled: true
      })
      .then(list => {
        for (const client of list) {
          if (client.url.startsWith(self.location.origin)) {
            client.navigate(target);
            return client.focus();
          }
        }

        return clients.openWindow(target);
      })
  );
});
