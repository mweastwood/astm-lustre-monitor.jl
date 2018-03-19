module Monitor

mutable struct OST
    name :: String
    kbytestotal :: Int
    kbytesfree  :: Int
    snapshot_time :: Float64
    read_bytes  :: Int
    write_bytes :: Int
end

function OST(name)
    OST(name, 0, 0, 0.0, 0, 0)
end

function OSTs()
    result = readstring(`lctl get_param devices`)
    lines  = split(result, "\n")
    line_words = [split(line) for line in lines]
    output = OST[]
    for words in line_words
        length(words) == 6 || continue
        words[3] == "osc"  || continue
        name = words[4]
        push!(output, OST(name))
    end
    measure_disk_space!.(output)
    measure_io!.(output)
    output
end

function measure!(ost)
    measure_disk_space!(ost)
    measure_io!(ost)
end

function measure_disk_space!(ost::OST)
    ost.kbytestotal = parse(Int, readstring(`lctl get_param -n osc.$(ost.name).kbytestotal`))
    ost.kbytesfree  = parse(Int, readstring(`lctl get_param -n osc.$(ost.name).kbytesfree`))
    ost
end

function measure_io!(ost::OST)
    stats = readstring(`lctl get_param -n osc.$(ost.name).stats`)
    lines = split(stats, "\n")
    line_words = [split(line) for line in lines]
    for words in line_words
        length(words) > 0 || continue
        if     words[1] == "snapshot_time"
            ost.snapshot_time = parse(Float64, words[2])
        elseif words[1] == "read_bytes"
            ost.read_bytes  = parse(Int, words[7])
        elseif words[1] == "write_bytes"
            ost.write_bytes = parse(Int, words[7])
        end
    end
end

mutable struct Tracker
    before :: Vector{OST}
    after  :: Vector{OST}
end

function Tracker()
    before = OSTs()
    sleep(0.01)
    after  = OSTs()
    Tracker(before, after)
end

function display(tracker::Tracker)
    N = length(tracker.before)
    @printf("                           OST Name │ Total Space │  Free Space │  Read Speed │ Write Speed \n")
    @printf("────────────────────────────────────┼─────────────┼─────────────┼─────────────┼─────────────\n")
    for idx = 1:N
        before = tracker.before[idx]
        after  = tracker.after[idx]
        Δt = after.snapshot_time - before.snapshot_time
        @printf("%35s │ %8.1f GB │ %8.1f GB │ %6.1f MB/s │ %6.1f MB/s\n",
                after.name, after.kbytestotal / (1024)^2, after.kbytesfree / 1024^2,
                (after.read_bytes  - before.read_bytes)  / Δt / 1024^2,
                (after.write_bytes - before.write_bytes) / Δt / 1024^2)
    end
end

function return_to_top(tracker::Tracker)
    N = length(tracker.before)
    for idx = 1:N+2
        print("\033[F") # go back to the top
    end
end

function track()
    tracker = Tracker()
    display(tracker)
    while true
        sleep(1)
        tracker.before = tracker.after
        tracker.after  = OSTs()
        return_to_top(tracker)
        display(tracker)
    end
end

function go()
    try
        track()
    catch exception
        if exception isa InterruptException
            quit()
        else
            rethrow(exception)
        end
    end
end

end

