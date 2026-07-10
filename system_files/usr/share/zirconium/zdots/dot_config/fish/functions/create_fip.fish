function fip --description 'Forward local ports through SSH'
    if test (count $argv) -lt 2
        echo 'Usage: fip <host> <port> [port2 ...]' >&2
        return 1
    end

    set -l host $argv[1]
    for port in $argv[2..]
        if not string match -qr '^[0-9]+$' -- $port; or test $port -lt 1; or test $port -gt 65535
            echo "Invalid port: $port" >&2
            return 1
        end

        ssh -f -N -L "$port:localhost:$port" "$host"
        and echo "Forwarding localhost:$port -> $host:$port"
    end
end
