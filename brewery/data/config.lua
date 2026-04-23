return {
  -----------------
  -- ShopK Settings
  -----------------

  -- Kromer sync node to use for shopk
  -- Example: https://kromer.reconnected.cc/api/krist/
  -- To use the official node, please keep nil (will change based on shopk library)
  syncNode = nil,
  -- Kromer private key to use for shopk
  --privatekey = "testing123",
  -- UNCOMMENT ABOVE LINE AND PUT IN YOUR PKEY FOR EVERYTHING TO WORK!

  -----------------
  -- Klog Settings
  -----------------

  -- Optional: explicit klog API key. If omitted, settings key klog.apiKey is used.
  --klogApiKey = "",

  -- Optional: force which ender_storage peripheral to use for klog staging.
  --klogPeripheral = "enderstorage_0",

  -- Optional: override klog endpoints.
  --klogApiUrl = "https://api.krawlet.cc/v1/",
  --klogWsUrl = "wss://api.krawlet.cc/v1/ws",

  -- Optional: inventory peripheral patterns to exclude from external staging.
  --klogInputExcludes = {"minecraft:chest_*"},
}
