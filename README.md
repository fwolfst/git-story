# Git::Story

## Description

Ruby gem containing an executable that abstracts a standard git workflow.

## Installation

The homepage of this library is located at

* `http://github.com/flori/git-story` .

Install system-wide with

```bash
gem install git-story
```
, or add it to your `Gemfile` and `bundle`.

## Synopsis

`git-story` sets up some git-hooks to ensure some conventions and provides
tooling to conveniently use named branches and integrations in a rather
specific development and deployment processes (at betterplace).

## Usage

```bash
$ git-story help
mkdir -p .git/hooks
# [two lines giving output about files copied to .git/hooks omitted]

Available commands are:
help                this help
setup               initialize git story config file and copy hooks if missing
current             output the current story branch if it is checked out
status              [STORY_ID] fetch status of current story, -n SECONDS refreshes
list                [AUTHOR] list all stories
details             [AUTHOR] list all stories with details
deploy tags         list all production deploy tags
deploys             output the times of all production deploys
deploy tags last    output the last production deploy tag
deploy last         output the time of the last production deploy
deploy log          [REF] output log of changes since last production deploy tag
deploy stories      [REF] List all stories scheduled for next deploy
deploy diff         [REF] output diff since last production deploy tag
deploy migrate diff [REF] output migration diff since last production deploy tag
create              [STORYID] create a story for story STORYID
switch              [PATTERN] switch to story matching PATTERN
delete              [PATTERN] delete story branch matching PATTERN
github              [BRANCH] open branch on github
pivotal             [BRANCH] open branch on pivotaltracker
semaphore           open project on semaphore
hotfix              [REF] create a hotfix branch from REF
```

## Author

Florian Frank mailto:flori@ping.de

## License

Apache License, Version 2.0 – See the [COPYING](COPYING) file in the source archive.
