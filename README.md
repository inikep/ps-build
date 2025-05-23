# Docker way
```
git clone https://github.com/Percona-Lab/ps-build --branch 8.x
cd ps-build
BRANCH=release-9.2.0-1 ./local/checkout

./docker/run-build centos:8
./docker/run-test-parallel-mtr centos:8
```

## Docker debug
```
git clone https://github.com/Percona-Lab/ps-build --branch 8.x
cd ps-build
BRANCH=release-9.2.0-1 ./local/checkout

./docker/run-build-debug centos:8
```

# Local way
```
git clone https://github.com/Percona-Lab/ps-build --branch 8.0
cd ps-build
sudo ./docker/install-deps

git checkout 8.x
BRANCH=release-9.2.0-1 ./local/checkout

./local/build-binary
./local/test-binary-parallel-mtr
```
