// Database initialization
function openIndexedDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open("POSLocalDB", 1);

    request.onupgradeneeded = (event) => {
      const db = event.target.result;
      if (!db.objectStoreNames.contains("orders")) {
        const store = db.createObjectStore("orders", { keyPath: "client_uuid" });
        store.createIndex("synced", "synced", { unique: false });
      }
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

// Background sync worker
async function syncOfflineOrders() {
  if (!navigator.onLine) return;

  const db = await openIndexedDB();
  const tx = db.transaction("orders", "readonly");
  const store = tx.objectStore("orders");
  const index = store.index("synced");

  const unsyncedOrders = await new Promise((resolve) => {
    const req = index.getAll(false);
    req.onsuccess = () => resolve(req.result);
  });

  if (unsyncedOrders.length === 0) return;

  try {
    const response = await fetch("/api/v1/sync/orders", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(unsyncedOrders),
    });

    const result = await response.json();

    if (response.ok && result.synced_uuids) {
      const writeTx = db.transaction("orders", "readwrite");
      const writeStore = writeTx.objectStore("orders");

      for (const uuid of result.synced_uuids) {
        const item = await new Promise((res) => {
          const req = writeStore.get(uuid);
          req.onsuccess = () => res(req.result);
        });

        if (item) {
          item.synced = true;
          writeStore.put(item);
        }
      }
      console.log(`Synced ${result.synced_uuids.length} orders.`);
    }
  } catch (error) {
    console.error("Sync error:", error);
  }
}

window.addEventListener("online", syncOfflineOrders);
setInterval(syncOfflineOrders, 30000);