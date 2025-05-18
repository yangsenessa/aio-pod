#!/bin/bash

# Print colored text
print_green() {
    echo -e "\033[0;32m$1\033[0m"
}

print_blue() {
    echo -e "\033[0;34m$1\033[0m"
}

print_red() {
    echo -e "\033[0;31m$1\033[0m"
}

FILE_SERVER_PORT=8001
EXEC_SERVER_PORT=8000

print_blue "Stopping file server on port $FILE_SERVER_PORT..."
PIDS=$(lsof -ti:$FILE_SERVER_PORT)
if [ -n "$PIDS" ]; then
    kill -9 $PIDS
    print_green "File server on port $FILE_SERVER_PORT stopped."
else
    print_red "No process found on port $FILE_SERVER_PORT."
fi

print_blue "Stopping execution server on port $EXEC_SERVER_PORT..."
PIDS=$(lsof -ti:$EXEC_SERVER_PORT)
if [ -n "$PIDS" ]; then
    kill -9 $PIDS
    print_green "Execution server on port $EXEC_SERVER_PORT stopped."
else
    print_red "No process found on port $EXEC_SERVER_PORT."
fi

print_green "All related aio-pod services stopped." 