function compress --description 'Create a tar.gz archive'
    if test (count $argv) -ne 1
        echo 'Usage: compress <file-or-directory>' >&2
        return 1
    end

    set -l input (string replace -r '/$' '' -- $argv[1])
    tar -czf "$input.tar.gz" -- "$input"
end
