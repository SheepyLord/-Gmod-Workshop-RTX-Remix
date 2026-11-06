-- Pure rolling-window budget. Expiry accounting is conservative when a particle dies early.
local Budget = {}
function Budget.New(rate, maximum)
    local b = { rate = rate, maximum = maximum, recent = {}, live = {}, total = 0 }
    function b:Prune(now)
        for i = #self.recent, 1, -1 do
            if self.recent[i] <= now - 1 then table.remove(self.recent, i) end
        end
        for i = #self.live, 1, -1 do
            if self.live[i] <= now then table.remove(self.live, i) end
        end
    end
    function b:Take(now, lifetime)
        self:Prune(now)
        if #self.recent >= self.rate or #self.live >= self.maximum then return false end
        self.recent[#self.recent + 1] = now
        self.live[#self.live + 1] = now + lifetime
        self.total = self.total + 1
        return true
    end
    function b:Reset()
        self.recent, self.live, self.total = {}, {}, 0
    end
    return b
end
return Budget
