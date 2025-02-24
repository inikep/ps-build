#!/bin/echo This script should be sourced in a shell, not executed directly

function build_and_run_sanitizer() {
    if [[ -z "$PS_BUILD_DIR" ]] || [[ -z "$WORK_DIR" ]] || [[ -z "$WORKSPACE" ]]; then
        echo "Error: PS_BUILD_DIR or WORK_DIR or WORKSPACE is not set."
        return 1
    fi

    # RESULTS_DIR has to be equal to RESULTS_DIR variable defined in /local/test-binary-parallel-mtr
    local RESULTS_DIR=$WORK_DIR/results

    # clear results from the last run
    if [[ -d $RESULTS_DIR ]]; then
        ls -la $RESULTS_DIR
        rm -rf $RESULTS_DIR
    fi

    # download "ps-build" repo and share it with 8.0/8.x branches
    if [[ ! -d "$PS_BUILD_DIR" ]]; then
        sudo mkdir -p $PS_BUILD_DIR
        sudo chown $USER:$USER $PS_BUILD_DIR
        git clone --branch 8.0 "$PS_BUILD_REPO" "$PS_BUILD_DIR" || { echo "Error: git clone failed"; return 1; }
        cd $PS_BUILD_DIR
        # call /docker/install-deps from 8.0 branch
        sudo ./docker/install-deps
    fi

    setup_git_repo $PS_BUILD_REPO $PS_BUILD_BRANCH $PS_BUILD_DIR
    cd $PS_BUILD_DIR

    # build from sources unless SKIP_BUILD=yes
    if [ "$SKIP_BUILD" != "yes" ]; then
        sudo rm -rf $WORK_DIR
        sudo mkdir -p $WORK_DIR
        sudo chown $USER:$USER $WORK_DIR
        sudo git clean -xdf
        # sudo chown -R $USER:$USER sources
        # /local/checkout uses env variables GIT_REPO and BRANCH
        ./local/checkout
        ./local/build-binary $WORK_DIR
    fi

    ./local/test-binary-parallel-mtr $WORK_DIR | tee $WORK_DIR/mtr-test.log

    cd $WORK_DIR
    mv mtr-test.log mtr-test.full-log
    filter_valgrind_log mtr-test.full-log mtr-test.log
    zstd -c mtr-test.log > mtr-test.log.zst

    grep -A16 "Conditional jump or move depends on uninitialised" mtr-test.log >mtr-test-valgrind-ConditionalJump.log || :
    grep -A16 "are definitely lost"         mtr-test.log >mtr-test-valgrind-definitelyLost.log || :
    grep -B128 -A128 "Invalid read of size" mtr-test.log >mtr-test-valgrind-InvalidRead.log || :
    grep -A16 "ERROR: .*Sanitizer"          mtr-test.log >mtr-test-Errors-Sanitizers.log || :
    grep -A16 "ERROR: AddressSanitizer"     mtr-test.log >mtr-test-Errors-AddressSanitizer.log || :
    grep -A16 "ERROR: LeakSanitizer"        mtr-test.log >mtr-test-Errors-LeakSanitizer.log || :

    ls -l
    cp $WORK_DIR/*.log* $WORKSPACE/
    cp $WORK_DIR/*.txt $WORKSPACE/
    cp $RESULTS_DIR/*.xml $WORKSPACE/
    cp $RESULTS_DIR/*.tar.gz $WORKSPACE/
}
