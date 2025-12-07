Config = {}

Config.Command = 'reimburse'

Config.Stash = {
    IdPrefix = 'reimburse_',
    LabelFormat = 'Reimbursement Locker - %s',
    Slots = 25,
    MaxWeight = 500000,
}

Config.AllowedGroups = {
    ['admin'] = true,
    ['owner'] = true
}

Config.LogSecurityEvents = false

Config.LockerLocations = {
    {
        coords = vector3(-269.87, -954.18, 30.22), -- Apartments
        heading = 27,
        prop = 'v_corp_postbox',
        distance = 1.8,
    },
    {
        coords = vector3(293.73, -617.30, 42.45), -- Hospital
        heading = 160,
        prop = 'v_corp_postbox',
        distance = 1.8,
    },
    {
        coords = vector3(604.78, 5.54, 75.04), -- VPD
        heading = 0,
        virtual = true, -- No prop
        distance = 1.8,
    },
}

