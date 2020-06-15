#/bin/bash
set -e 
### Configuration ###
GROUP="wf.frk.f3b"
NAME="f3b"
if [ "$VERSION" = "" ];
then
    VERSION="-SNAPSHOT" #This is automatically replaced with tag name in travis
fi
#####################

rm -Rf build/tmp
mkdir -p build/tmp

if [ ! -f "build/bash_colors.sh" ];
then
    wget  -q https://raw.githubusercontent.com/maxtsepkov/bash_colors/738f82882672babfaa21a2c5e78097d9d8118f91/bash_colors.sh -O build/bash_colors.sh
fi
source build/bash_colors.sh



function compile {
    if [ ! -f build/protoc ]; then
        clr_green "Retrieve protoc..."
        mkdir -p build/tmp/protobuf
        cd build/tmp/protobuf
        wget -q "https://github.com/google/protobuf/releases/download/v2.6.1/protobuf-2.6.1.tar.gz" -O protobuf.tar.gz
        tar -xzf protobuf.tar.gz
        rm -Rf protobuf.tar.gz
        cd *
        clr_green "Compile protoc..."
        if [ "$1" = "osx" ]; then
            ./configure CC=clang CXX=clang++ CXXFLAGS='-std=c++11 -stdlib=libc++ -O3 -g' LDFLAGS='-stdlib=libc++' LIBS="-lc++ -lc++abi"
            make -j 4 
        else
            ./configure          
            make -j 4 
        fi
        cp src/protoc ../../../
        cp -Rf src/.libs ../../../

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
    rm -Rf build/src
    cp -Rf src build/
    cd build
    export LD_LIBRARY_PATH=./.libs/

    extensions=$2
    if [ "$extensions" != "" ];
    then
        oifs=$IFS
        IFS=","
        for ext in "$extensions"
        do
            echo "Build extension $ext"
            source src/$ext/extension.sh
            dest="src/f3b/datas.proto"
            head -n 1 $dest > tmp.f
            echo "$EXT_IMPORTS" >> tmp.f
            tail -n +2  "$dest" >> tmp.f
            mv tmp.f "$dest"

            head -n -1  "$dest" > tmp.f
            echo "$EXT_DATA" >> tmp.f
            tail -n 1 src/f3b/datas.proto >>tmp.f
            mv tmp.f "$dest"

            # for extf in src/$ext/*.extension; do
            #     n=$(basename -- "$extf")
            #     n="${n%.*}"
            #     echo "Extend $n.proto with $extf"
            #     cat $extf >> src/f3b/$n.proto
            # done
           ./protoc --cpp_out=./cpp --python_out=./python --java_out=./java --proto_path=src  src/$ext/*.proto
        done
        IFS=$oifs
    fi
    echo "Generate protobuf src"
    ./protoc --cpp_out=./cpp --python_out=./python --java_out=./java --proto_path=src  src/f3b/*.proto
    cd ..
}

function clean {
    rm -Rf build
}
function assemble {
    if [ ! -f build/protobuf.jar ]; then
        clr_green "Download protobuf runtime for java..."
        wget -q "https://repo1.maven.org/maven2/com/google/protobuf/protobuf-java/2.6.1/protobuf-java-2.6.1.jar" -O build/protobuf.jar
        echo "Downloaded"
    fi 
    rm -Rf build/release || true
    mkdir -p build/release 

    clr_green "Build C++ source release..."
    cd build/cpp
        echo $PWD

    cmd="`which zip` ../release/$NAME-$VERSION-cpp.zip -r *"
    clr_escape "$(echo $cmd)" $CLR_BOLD $CLR_BLUE
    $cmd
    cd ..
     
    clr_green "Build Python release..." 
    cd python    
    cmd="`which zip` -0 ../release/$NAME-$VERSION-python.zip -r *"
    clr_escape "$(echo $cmd)" $CLR_BOLD $CLR_BLUE
    $cmd
    cd ..
    
    clr_green "Build Java source release..."    
    cmd="`which jar` cf release/$NAME-$VERSION-sources.jar -C java ."
    clr_escape "$(echo $cmd)" $CLR_BOLD $CLR_BLUE
    $cmd
    
    clr_green "Build Java binary release..."
    mkdir -p tmp/java_build
    cp -Rf java/* tmp/java_build
    find  tmp/java_build -type f -name '*.java' > java-src.txt
    cmd="`which javac` -source 1.7 -target 1.7 -Xlint:none -cp protobuf.jar @java-src.txt"
    clr_escape "$(echo $cmd)" $CLR_BOLD $CLR_BLUE
    $cmd  

    find tmp/java_build -type f -name '*.java'  -delete
    cmd="`which jar` cf release/$NAME-$VERSION.jar -C tmp/java_build ."
    clr_escape "$(echo $cmd)" $CLR_BOLD $CLR_BLUE
    $cmd


    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<project
  xmlns=\"http://maven.apache.org/POM/4.0.0\"
  xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"
  xsi:schemaLocation=\"http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd\">

  <modelVersion>4.0.0</modelVersion>
      <groupId>$GROUP</groupId>
    <artifactId>$NAME</artifactId>
    <version>$VERSION</version>

  <name>$NAME</name>
  <description></description>
  <url></url>
</project>" > release/$NAME-$VERSION.pom

    cd ..
}

function deployToLocal {
    target_dir="$HOME/.m2/repository/"${GROUP//./\/}"/$NAME/$VERSION/"
    mkdir -p $target_dir
    clr_green "Copy build/release/$NAME-$VERSION*  in $target_dir"
    cp -Rf build/release/$NAME-$VERSION* $target_dir
}

function deployToRemote {
    cd build/release
    for f in *
    do
        target_dir=${GROUP//./\/}
        curl -X PUT  -T  $f -u$BINTRAY_USER:$BINTRAY_API_KEY\
            "https://api.bintray.com/content/riccardo/f3b/f3b/$VERSION/$target_dir/$NAME/$VERSION/$f?publish=1&override=1"
    done
    cd ../../
    echo $VERSION > build/tmp/version.txt
    curl -X PUT  -T  build/tmp/version.txt -u$BINTRAY_USER:$BINTRAY_API_KEY \
           "https://api.bintray.com/content/riccardo/f3b/f3b/latest/$target_dir/version.txt?publish=1&override=1"

}

function deployToMinio {
    cd build/release
    for f in *
    do
        target_dir=${GROUP//./\/}
       mc  cp $f $2/$target_dir/$NAME/$VERSION/$f
    done
    cd ../../
    echo $VERSION > build/tmp/version.txt
    mc  cp  build/tmp/version.txt $2/$target_dir/version.txt
}





function jenkins {
    compile "linux" "cr_ext"
    assemble
     if [ "$1" = "minio" ];
    then
        deployToMinio $@
    fi
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
    compile $TRAVIS_OS_NAME "cr_ext"
    assemble
    if [ "$DEPLOY" != "true" ];
    then
        exit 0
    fi  
    deployToRemote
}

function compileAndDeployToLocal {
    compile $@
    assemble $@
    deployToLocal $@
}

function compileAndDeployToRemote {
    compile  $@ 
    assemble $@
    deployToRemote $@
}

if [ "$1" = "" ];
then
    echo "Usage: make.sh target [OS] [EXTENSIONS CSV]"
    echo " - Targets: clean,compile,assemble,deployToLocal,deployToRemote,travis,compileAndDeployToLocal,compileAndDeployToRemote"
    echo " - Example: ./make.sh compile linux ext1,ext2,ext3"
    exit 0
fi
echo "Run $@"
$@
clr_magenta "+ Done!"
