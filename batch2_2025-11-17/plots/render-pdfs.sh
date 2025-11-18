#!/bin/bash
find . | grep -P ".pdf$" | parallel "convert -verbose -density 300 -trim {} -quality 100 -flatten -sharpen 0x1.0 {.}_render.png"
