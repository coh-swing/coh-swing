FxInfo
Condition
    On Time
    Time 0
    Event
        EName DroneAttachment1
        Type Create
        At Origin
        Inherit All
        Update All
        Bhvr Behaviors/DroneSpin.bhvr
        Geom OverHeadDummy
    End
    Event
        EName DroneAttachment
        Type Create
        At DroneAttachment1
        Inherit All
        Update All
        Bhvr Behaviors/DroneSpinLocal.bhvr
        Geom centerdummy
    End
    Event
        EName Drone
        Type Create
        At DroneAttachment
        Inherit All
        Update All
        Bhvr Behaviors/DroneFade.bhvr
        Geom FX_Drone
        Part POWERS/GADGETS/glow.part
    End
End
End
