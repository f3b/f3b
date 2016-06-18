#/bin/bash

### Configuration ###
GROUP="wf.frk.f3b"
NAME="f3b"
VERSION="dev" #This is automatically replaced with tag name in travis
#####################

rm -Rf build/tmp
mkdir -p build/tmp

if [ ! -f "build/bash_colors.sh" ];
then
    wget  -q https://raw.githubusercontent.com/maxtsepkov/bash_colors/738f82882672babfaa21a2c5e78097d9d8118f91/bash_colors.sh -O build/bash_colors.sh
fi
source build/bash_colors.sh

function checkErrors {
    if [ $? -ne 0 ]; then 
        clr_red "Build failed."
        exit 1; 
    fi
}



function compile {
    if [ ! -f build/protoc ]; then
        clr_green "Retrieve protoc..."
        mkdir -p build/tmp/protobuf
        cd build/tmp/protobuf
        wget -q "https://github.com/google/protobuf/releases/download/v2.6.1/protobuf-2.6.1.tar.gz" -O protobuf.tar.gz
        checkErrors
        tar -xzf protobuf.tar.gz
        rm -Rf protobuf.tar.gz
        cd *
        clr_green "Compile protoc..."
        if [ "$1" = "osx" ]; then
            ./configure CC=clang CXX=clang++ CXXFLAGS='-std=c++11 -stdlib=libc++ -O3 -g' LDFLAGS='-stdlib=libc++' LIBS="-lc++ -lc++abi"
            checkErrors
            make -j 4 
        else
            ./configure          
            checkErrors
            make -j 4 
        fi
        checkErrors
        cp src/protoc ../../../
        cd ../../../
        chmod +x protoc
        cd ..
    fi
    rm -Rf build/cpp
    rm -Rf build/java
    rm -Rf build/python
    mkdir -p build/cpp
    mkdir -p build/java
    mkdir -p build/python
    clr_green "Compile protocol..."
    build/protoc --cpp_out=build/cpp --python_out=build/python --java_out=build/java --proto_path=src  src/f3b/*.proto
    checkErrors
}

function clean {
    rm -Rf build
}
function assemble {
    if [ ! -f build/protobuf.jar ]; then
        clr_green "Download protobuf runtime for java..."
        wget -q "http://central.maven.org/maven2/com/google/protobuf/protobuf-java/2.6.1/protobuf-java-2.6.1.jar" -O build/protobuf.jar
        checkErrors
    fi 
    mkdir -p build/release

    clr_green "Build C++ source release..."
    cd build/cpp
    cmd="`which zip` ../release/$NAME-$VERSION-cpp.zip -r *"
    clr_escape "$(echo $cmd)" $CLR_BOLD $CLR_BLUE
    $cmd
    checkErrors
    cd ..
     
    clr_green "Build Python release..." 
    cd python    
    cmd="`which zip` -0 ../release/$NAME-$VERSION-python.zip -r *"
    clr_escape "$(echo $cmd)" $CLR_BOLD $CLR_BLUE
    $cmd
    checkErrors
    cd ..
    
    clr_green "Build Java source release..."    
    cmd="`which jar` cf release/$NAME-$VERSION-sources.jar -C java ."
    clr_escape "$(echo $cmd)" $CLR_BOLD $CLR_BLUE
    $cmd
    checkErrors
    
    clr_green "Build Java binary release..."
    mkdir -p tmp/java_build
    cp -Rf java/* tmp/java_build
    find  tmp/java_build -type f -name '*.java' > java-src.txt
    cmd="`which javac` -source 1.7 -target 1.7 -Xlint:none -cp protobuf.jar @java-src.txt"
    clr_escape "$(echo $cmd)" $CLR_BOLD $CLR_BLUE
    $cmd  
    checkErrors      
    find tmp/java_build -type f -name '*.java'  -delete
    cmd="`which jar` cf release/$NAME-$VERSION.jar -C tmp/java_build ."
    clr_escape "$(echo $cmd)" $CLR_BOLD $CLR_BLUE
    $cmd
    checkErrors
    cd ..
}

function deployToLocal {
    target_dir="$HOME/.m2/repository/"${GROUP//./\/}"/$NAME/"
    mkdir -p $target_dir
    clr_green "Copy build/release/$NAME-$VERSION*  in $target_dir"
    cp build/release/$NAME-$VERSION* $target_dir
}

function deployToRemote {
    cd build/release
    for f in *
    do
        target_dir=${GROUP//./\/}
        curl -X PUT  -T  $f -u$BINTRAY_USER:$BINTRAY_API_KEY\
            "https://api.bintray.com/content/riccardo/f3b/f3b/$VERSION/$target_dir/$f?publish=1&override=1"
    done
    cd ../../
    echo $VERSION > build/tmp/version.txt
    curl -X PUT  -T  build/tmp/version.txt -u$BINTRAY_USER:$BINTRAY_API_KEY \
           "https://api.bintray.com/content/riccardo/f3b/f3b/latest/$target_dir/version.txt?publish=1&override=1"

}

function travis {
    DEPLOY="false"
    VERSION=$TRAVIS_COMMIT
    if [ "$TRAVIS_TAG" != "" -a "$TRAVIS_OS_NAME" = "linux" ];
    then
        echo "Deploy for $TRAVIS_TAG."
        VERSION=$TRAVIS_TAG
        DEPLOY="true"    
    fi
    compile $TRAVIS_OS_NAME
    assemble
    if [ "$DEPLOY" != "true" ];
    then
        exit 0
    fi  
    deployToRemote
}

function compileAndDeployToLocal {
    compile
    assemble
    deployToLocal
}

function compileAndDeployToRemote {
    compile
    assemble
    deployToRemote
}

if [ "$1" = "" ];
then
    echo "Usage: make.sh target"
    echo " - Targets: clean,compile,assemble,deployToLocal,deployToRemote,travis,compileAndDeployToLocal,compileAndDeployToRemote"
    exit 0
fi
clr_magenta "Run $1..."
$1 ${*:2}
clr_magenta "+ Done!"
