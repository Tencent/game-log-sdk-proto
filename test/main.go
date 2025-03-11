package main

import (
	"fmt"
	"strconv"

	"github.com/gogo/protobuf/types"
	jsoniter "github.com/json-iterator/go"
	"google.golang.org/protobuf/types/known/timestamppb"

	v3 "tglog-proto/pbgo"
)

var (
	json = jsoniter.Config{ //nolint:deadcode,unused,varcheck
		EscapeHTML:             true,
		SortMapKeys:            true,
		ValidateJsonRawMessage: true,
		// UseNumber:              true, // 因为配置中有64位整数需要解析，所以打开该选项
	}.Froze()
	serverAddrField = ""
)

func main() {
	var pbLogs = make([]*v3.Log, 0, 10)
	for i := 0; i < 10; i++ {
		pbLogs = append(pbLogs, &v3.Log{Name: strconv.Itoa(i), Content: "msg:" + strconv.Itoa(i), Seq: uint64(1152921504606846976 + i)})
	}

	logReq := &v3.Req_LogReq{
		LogReq: &v3.LogReq{
			Labels:      map[string]string{},
			Annotations: map[string]string{},
			Logs:        pbLogs,
		},
	}

	ts := timestamppb.Now()

	req := &v3.Req{}

	header := &v3.ReqHeader{
		AppID:    "appID",
		AppName:  "appName",
		AppVer:   "appVer",
		SdkLang:  "language",
		SdkVer:   "sdkVersion",
		SdkOS:    "platform",
		Network:  "network",
		ProtoVer: "protoVer",
		HostIP:   "localIP",
		Ts:       &types.Timestamp{Seconds: ts.Seconds, Nanos: ts.Nanos},
		Token:    "token",
		Sig:      "", // todo sig
	}
	_ = header
	req.ReqID = "reqID"
	req.AppMetaData = []byte("appMetaData")
	req.Req = logReq

	json, err := jsoniter.MarshalIndent(req, "", "    ")
	if err != nil {
		fmt.Println(err)
		return
	}

	fmt.Println(string(json))
}
