#!/bin/bash

function do_nothing(){
	local ret="$1"
	echo 'pqp - do nothing'
	printf -v "$1" "%d" "$ret"
}
