function decompress --description 'Extract a tar.gz archive'
    if test (count $argv) -lt 1
        echo 'Usage: decompress <archive.tar.gz> [tar-options]' >&2
        return 1
    end

    tar -xzf $argv
end
