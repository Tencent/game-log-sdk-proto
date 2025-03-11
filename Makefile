export PATH:=${PATH}:./plugins

.PHONY : clean all

all : tglog_v3.proto
ifeq ($(OS),Windows_NT)
	protoc/bin/protoc.exe --cpp_out=./cpp tglog_v3.proto
	protoc/bin/protoc.exe --java_out=./java tglog_v3.proto
	protoc/bin/protoc.exe --go_out=./pbgo --plugin=plugins/protoc-gen-go.exe tglog_v3.proto
	mv pbgo/github.com/tencent/game-log-sdk-proto/pbgo/* go/
	rm -rf pbgo/github.com
	protoc/bin/protoc.exe --c_out=./c --plugin=plugins/protoc-gen-c.exe tglog_v3.proto
else
	protoc/bin/protoc --cpp_out=./cpp tglog_v3.proto
	protoc/bin/protoc --java_out=./java tglog_v3.proto
	#protoc/bin/protoc --go_out=./pbgo --plugin=plugins/protoc-gen-go tglog_v3.proto
	protoc -I=. -I=${GOPATH}/pkg/mod -I=${GOPATH}/pkg/mod/github.com/gogo/protobuf@v1.3.2/protobuf --plugin=plugins/protoc-gen-gogofast --gogofast_out=Mgoogle/protobuf/any.proto=github.com/gogo/protobuf/types,Mgoogle/protobuf/duration.proto=github.com/gogo/protobuf/types,Mgoogle/protobuf/struct.proto=github.com/gogo/protobuf/types,Mgoogle/protobuf/timestamp.proto=github.com/gogo/protobuf/types,Mgoogle/protobuf/wrappers.proto=github.com/gogo/protobuf/types:./pbgo tglog_v3.proto
	mv pbgo/github.com/tencent/game-log-sdk-proto/pbgo/* pbgo/
	rm -rf pbgo/github.com
	protoc/bin/protoc --c_out=./c --plugin=plugins/protoc-gen-c tglog_v3.proto
endif



clean :
	rm -rf cpp/*
	rm -rf java/*
	rm -rf pbgo/*
	rm -rf c/*
