# 协议



## 说明

本仓库保存TGLogV3版本的协议，作为客户端和服务器端共享的通信协议，单独用一个仓库保存，使用的时候，C/C++/JAVA语言请用***submoule***的方式引用特定版本到客户端或者服务器端的项目中再使用，Go语言请直接import生成的代码。



## 格式

> **重要说明：**
>
> - **如果不鉴权也不签名，可以不上报请求头；**
> - **如果鉴权或者签名，请求头需要加密传输，避免token泄漏；**

### 协议包组成

| 帧头   | 包头 | 包体 |
| ------ | ---- | ---- |
| 10字节 | 变长 | 变长 |

### 帧头

| 魔数                  | 协议包长                                                | 标记字段 | 包头长度 | 保留字段 |
| --------------------- | ------------------------------------------------------- | -------- | -------- | -------- |
| 2字节，固定为：0x0601 | 4字节，包括帧头（10）、包头（变长）、包体（变长）的长度 | 1字节    | 2字节    | 1字节    |

### 标记位

```protobuf
enum Flag{
  FLAG_NONE = 0;                      //无
  FLAG_COMPRESSED = 1;                //消息已压缩
  FLAG_ENCRYPTED = 2;                 //消息已加密
  FLAG_COMPRESSED_HEADER = 4;         //消息头已压缩
  FLAG_ENCRYPTED_HEADER = 8;          //消息头已加密
}
```
### 请求头/请求

```protobuf
//请求头
message ReqHeader{
  string appID = 1;                   //业务ID
  string appName = 2;                 //业务名
  string appVer = 3;                  //业务版本号
  string sdkLang = 4;                 //SDK语言
  string sdkVer = 5;                  //SDK版本号
  string sdkOS = 6;                   //SDK操作系统
  string network = 7;                 //网络协议，tcp/udp
  string protoVer = 8;                //协议版本号
  string hostIP = 9;                  //客户端IP
  google.protobuf.Timestamp ts = 10;  //时间戳
  string token = 11;                  //令牌，公网环境才需要
  string tokenType = 12;              //令牌类型，支持bearer/tglog两种token，bearer即JWT，tglog为自定义的一种token
  string sig = 13;                    //签名，公网环境才需要
}

//请求
// 请求因为涉及到鉴权、签名，将请求头和请求包体分开，
// 客户端构造请求包体，压缩、加密、签名，再构造请求头，
// 服务器先解析请求头，鉴权、校验签名，再处理请求包体。
message Req{
  string reqID = 1;                   //请求ID
  bytes appMetaData = 2;              //应用层元数据，可以携带任何数据，在响应中原样返回
  oneof req{
    AuthReq authReq = 11;             //鉴权请求
    LogReq logReq = 12;               //日志请求
    HeartbeatReq heartbeatReq = 13;   //心跳请求
  }
}
```

### 响应头/响应

```protobuf
//响应头
message RspHeader{
  int32 code = 1;                     //错误码
  string msg = 2;                     //错误信息
  string reqID = 3;                   //请求ID
  bytes appMetaData = 4;              //应用层元数据
}

//响应
message Rsp{
  RspHeader header = 1;               //响应头，为了简化响应的处理，响应头和响应包体合并 ，客户端直接解包即可
  oneof rsp{
    AuthRsp authRsp = 11;             //鉴权响应
    LogRsp logRsp = 12;               //日志响应
    HeartbeatRsp heartbeatRsp = 13;   //心跳请求
  }
}
```

### 鉴权

鉴权通过请求头的appID和token字段携带的数据实现。

### 签名

#### 签名算法

sig = hex( md5( URI/ReqHeader.network + Method/ReqHeader.hostIP + token + ts + md5( body ) ) )，小写。即将URI（/tglog/v1/push或者/tglog/v3/push）或ReqHeader.network、Method（POST）或ReqHeader.hostIP、token、ts（8字节）、实际传输的数据的md5值（16字节）按**字节**拼接（注意拼接顺序），算md5摘要，再转成小写16进制字符串。

| 顺序 | 字段                                | 长度（字节）                    |
| ---- | ----------------------------------- | ------------------------------- |
| 1    | URI/ReqHeader.network               | URI/ReqHeader.network实际长度   |
| 2    | Method/ReqHeader.hostIP             | Method/ReqHeader.hostIP实际长度 |
| 3    | token                               | token实际长度                   |
| 5    | ts                                  | 8                               |
| 6    | md5(包体，如果压缩则是压缩后的数据) | 16字节                          |

> 说明：
>
> 1、使用token而不是app_key，是因为上报日志是高频操作，每条日志都去查业务的key会有很大的性能损耗；
>
> 2、最终的sig和包体的md5分开计算，是为了避免实现的时候拼接时进行大量的内存拷贝。

#### 签名代码参考

```go
package sign

import (
	"bytes"
	"crypto/md5"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"strings"
	"time"
)

// signature errors
var (
	ErrExpiredSig = errors.New("expired signature")
	ErrInvalidSig = errors.New("invalid signature")
)

// Sign signs a request
func Sign(uri, method, token string, ts int64, data []byte) string {
	md5sum := md5.Sum(data)
	return signData(uri, method, token, ts, md5sum[:])
}

// Verify a request
func Verify(sig, uri, method, token string, data []byte, ts, timeout int64) error {
	if expired(ts, timeout) {
		return ErrExpiredSig
	}

	localSig := Sign(uri, method, token, ts, data)
	if localSig != sig {
		return ErrInvalidSig
	}

	return nil
}

func signData(uri, method, token string, ts int64, dataList ...[]byte) string {
	var bb bytes.Buffer
	dataLen := 0
	for _, data := range dataList {
		dataLen += len(data)
	}
	bb.Grow(len(uri) + len(method) + len(token) + 8 + dataLen)

	// 按顺序拼接
	bb.WriteString(uri)
	bb.WriteString(method)

	bb.WriteString(token)

	var tsBuf [8]byte
	binary.LittleEndian.PutUint64(tsBuf[:], uint64(ts))
	bb.Write(tsBuf[:])

	for _, data := range dataList {
		bb.Write(data)
	}

	md5sum := md5.Sum(bb.Bytes())
	return strings.ToLower(hex.EncodeToString(md5sum[:]))
}

func expired(ts int64, timeout int64) bool {
	if timeout <= 0 {
		return false
	}

	return time.Now().After(time.Unix(ts+timeout, 0))
}

```



## 压缩与加密

### 压缩

支持**snappy**压缩。

### 加密

密钥分配：

由运营团队按业务分配，保存在客户端与服务器配置文件。

加密算法：**AES+PKCS7填充**。

### 顺序

如果同时压缩与加密，先压缩再加密，请遵守以下顺序编解码：

#### 编码

1. 填充Req或Rsp；
2. 把Req或Rsp打包成[]byte；
3. 压缩；
5. 加密；
5. 填充帧头，记得填充标记字段（0x01|0x02）；
6. 将Msg打包成[]byte，发送到网络上。

#### 解码

1. 收包，解析帧头标记位；
2. 如果加密，解密；
3. 如果压缩，解压；
4. 解包成Req或Rsp；
5. 使用Req或Rsp。



## 生成代码

### 依赖

- [protobuf](https://github.com/protocolbuffers/protobuf/releases)

- [protobuf-c](https://github.com/protobuf-c/protobuf-c)


- [protobuf-go](https://github.com/protocolbuffers/protobuf-go)

### 生成代码

执行：make

## 更新规则

- 稳定后的每次更新，请修改[tglog_v3.proto](./tglog_v3.proto)中的版本号；
- 稳定后的每次更新，请修改[CHANGELOG.md](./CHANGELOG.md),增加修改说明；
- 稳定后的每次更新，请重新生成代码；
- 稳定后的每次更新，请打上tag，tag标签与版本号一致，如v0.1.0；