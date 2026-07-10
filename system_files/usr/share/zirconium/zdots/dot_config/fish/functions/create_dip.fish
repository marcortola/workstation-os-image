function dip --description 'Stop SSH port forwards'
    if test (count $argv) -eq 0
        echo 'Usage: dip <port> [port2 ...]' >&2
        return 1
    end

    for port in $argv
        if not string match -qr '^[0-9]+$' -- $port; or test $port -lt 1; or test $port -gt 65535
            echo "Invalid port: $port" >&2
            return 1
        end

        if pkill -f "ssh.*-L $port:localhost:$port"
            echo "Stopped forwarding port $port"
        else
            echo "No forwarding on port $port"
        end
    end
end
