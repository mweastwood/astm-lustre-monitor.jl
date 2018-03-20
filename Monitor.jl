module Monitor

const me = readchomp(`hostname`)
const machines = [@sprintf("astm%02d", astm) for astm=4:13]

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
    result = readstring(`pdsh -w astm\[04-13\] /usr/sbin/lctl get_param -n devices`)
    lines  = split(result, "\n")
    line_words = [split(line) for line in lines]
    output = Dict(machine => OST[] for machine in machines)
    for words in line_words
        length(words) == 7 || continue
        words[4] == "osc"  || continue
        machine = strip(words[1], ':')
        name    = words[5]
        push!(output[machine], OST(name))
    end
    measure!(output)
    output
end

function names()
    output = Dict{String, String}()
end

function measure!(osts)
    measure_disk_space!.(osts[me])
    for machine in machines
        measure_io!(osts[machine], machine)
    end
end

function measure_disk_space!(ost::OST)
    ost.kbytestotal = parse(Int, readstring(`lctl get_param -n osc.$(ost.name).kbytestotal`))
    ost.kbytesfree  = parse(Int, readstring(`lctl get_param -n osc.$(ost.name).kbytesfree`))
    ost
end

function measure_io!(osts::Vector{OST}, machine)
    cmd = `/usr/sbin/lctl get_param osc.\*OST\*.stats`
    stats = readstring(`pdsh -w $machine $cmd`)
    lines = split(stats, "\n")
    line_words = [split(line) for line in lines]
    local current_ost
    for words in line_words
        length(words) > 0 || continue
        if length(words) == 2
            word = words[2]
            for ost in osts
                if contains(word, ost.name)
                    current_ost = ost
                    break
                end
            end
        end
        if     words[2] == "snapshot_time"
            current_ost.snapshot_time = parse(Float64, words[3])
        elseif words[2] == "read_bytes"
            current_ost.read_bytes  = parse(Int, words[8])
        elseif words[2] == "write_bytes"
            current_ost.write_bytes = parse(Int, words[8])
        end
    end
end

mutable struct Tracker
    before :: Dict{String, Vector{OST}}
    after  :: Dict{String, Vector{OST}}
end

function Tracker()
    before = OSTs()
    sleep(0.01)
    after  = OSTs()
    Tracker(before, after)
end

function display(tracker)
    N = length(tracker.before[me])

    @printf("┌──────────┬──────────")
    for machine in machines
        @printf("┬─────────")
    end
    @printf("┐\n")

    @printf("│          │  Free/GB │")
    for machine in machines
        @printf(" %7s │", machine)
    end
    @printf("\n")
    @printf("│     Name │ Total/GB │")
    for machine in machines
        @printf(" %7s │", "MB/s")
    end
    @printf("\n")

    for idx = 1:N
        @printf("├──────────┼──────────")
        for machine in machines
            @printf("┼─────────")
        end
        @printf("┤\n")

        # FIRST LINE
        before = tracker.before[me][idx]
        after  = tracker.after[me][idx]
        @printf("│ %8s │ %8.1f │", prune(after.name), after.kbytesfree / 1024^2)

        for machine in machines
            before = tracker.before[machine][idx]
            after  = tracker.after[machine][idx]
            Δt = after.snapshot_time - before.snapshot_time
            @printf(" r %5.1f │", (after.read_bytes - before.read_bytes) / Δt / 1024^2)
        end
        @printf("\n")

        # SECOND LINE
        before = tracker.before[me][idx]
        after  = tracker.after[me][idx]
        @printf("│ %8s │ %8.1f │", "", after.kbytestotal / 1024^2)

        for machine in machines
            before = tracker.before[machine][idx]
            after  = tracker.after[machine][idx]
            Δt = after.snapshot_time - before.snapshot_time
            @printf(" w %5.1f │", (after.write_bytes - before.write_bytes) / Δt / 1024^2)
        end
        @printf("\n")
    end

    @printf("└──────────┴──────────")
    for machine in machines
        @printf("┴─────────")
    end
    @printf("┘\n")
end

function prune(name)
    m = match(r"OST[0-f]{4}", name)
    m.match
end

function return_to_top(tracker::Tracker)
    N = length(tracker.before[me])
    for idx = 1:3N+4
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

function main()
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

