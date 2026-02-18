#!/usr/bin/env bash
sudo docker-compose -f docker-compose.yml up --scale worker=1 --build

sudo docker-compose -f ssl-docker-compose.yml up --build
