#!/bin/sh
umask 002

rm -rf ../winetestbot.new/*
svn export --force file:///srv/svn/repos_winetestbot/trunk ../winetestbot.new
rm -rf ../winetestbot.old/*
mv ../winetestbot/* ../winetestbot.old
mv ../winetestbot.new/* ../winetestbot
cp -p ../winetestbot.old/lib/WineTestBot/ConfigLocal.pl ../winetestbot/lib/WineTestBot
