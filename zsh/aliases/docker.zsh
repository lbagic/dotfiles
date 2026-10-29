#!/usr/bin/env zsh

alias docker-redis='
    docker run --rm -d --name redis-db \
        -p 6379:6379 \
        -p 8001:8001 \
        redis/redis-stack;
    echo "Redis port: 6379; Web UI: http://localhost:8001; Username: admin; Password: (none)"
'
alias docker-postgres='
    docker run -d --rm     \
        --name postgres-db \
        -p 5432:5432       \
        -e POSTGRES_DB=postgres \
        -e POSTGRES_PASSWORD=postgres \
        postgres;
    echo "Credentials: postgres:postgres; Database: postgres; Port: 5432"
'

alias dcup="docker compose up"
alias fdcup="docker compose up --build --force-recreate"