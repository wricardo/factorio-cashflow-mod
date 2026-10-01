-- Top-left tile of each station. Every station flows east.
return {
  -- The ledger stays in the open centre of the campus so players can read it
  -- while following the belts between stations.
  ledger = { x = -23, y = 12 },
  surface = "cashflow",
  spawn = { x = -30, y = 0 },
  stations = {
    { key = "paycheck", kind = "emitter", x = -46, y = -12 },
    { key = "needs", kind = "emitter", x = -46, y = -4 },
    { key = "wants", kind = "emitter", x = -46, y = 4 },
    { key = "cashflow", kind = "cashflow", x = -24, y = -6 },
    { key = "debt", kind = "debt", x = 0, y = -14 },
    { key = "vault", kind = "vault", x = 0, y = 8 },
  },
}
