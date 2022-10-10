# scripts in path

```
for f in $PWD/bin/*; do ln -s "$f" ~/bin/"fleet-${f##*/}"; done
# old names, used in some scripts
for f in $PWD/bin/{import-images-k3d,setup-fleet,setup-fleet-downstream}; do ln -s "$f" ~/bin/"fleetdev-${f##*/}"; done
```

all scripts use relative paths, cd to the git repo checkout first.
