#!/bin/bash
docker network inspect ignition-docker &> /dev/null || docker network create ignition-docker