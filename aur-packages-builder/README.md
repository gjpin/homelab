Build docker image
```bash
docker build -t aur-builder .
```

Run container
```bash
docker run --rm \
  -v ~/.ssh/id_ecdsa:/home/builder/.ssh/id_ecdsa:ro \
  -v "$PWD/build_packages.sh:/home/builder/build_packages.sh:ro" \
  aur-base bash /home/builder/build_packages.sh
```