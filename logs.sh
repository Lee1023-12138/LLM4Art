#!/usr/bin/env bash
cd "$(dirname "$0")"
pm2 logs llm4art-server llm4art-static
