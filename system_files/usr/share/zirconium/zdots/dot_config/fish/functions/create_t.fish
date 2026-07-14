function t --description "Attach or create the durable tmux session (main)"
    tmux new-session -A -s main $argv
end
