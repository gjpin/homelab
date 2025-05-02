Build docker image
```bash
docker build -t aur-builder .
```

Run container
```bash
docker run --rm \
  -v ~/.ssh:/home/builder/.ssh:ro \
  -v "$PWD/repo:/repo" \
  -v "$PWD/run-build.sh:/home/builder/run-build.sh:ro" \
  aur-base bash /home/builder/run-build.sh
```