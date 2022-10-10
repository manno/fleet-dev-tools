# scripts in path

```
for f in $PWD/bin/*; do ln -s "$f" ~/bin/"fleetdev-${f##*/}"; done
```

all scripts use relative paths, cd to the git repo checkout first.
