import NIO

final class ProduceInboundWriteWhenAnXGetsWrittenHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = self.unwrapOutboundIn(data)

        if buffer.readableBytesView.first == UInt8(ascii: "X") {
            context.fireChannelRead(self.wrapInboundOut(buffer))
        }

        context.write(data, promise: promise)
    }
}

final class EchoHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("received '\(String(decoding: self.unwrapInboundIn(data).readableBytesView, as: Unicode.UTF8.self))'")
        context.writeAndFlush(data, promise: nil)
    }
}

final class NaiveTwoByteFramingHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    var buffer: ByteBuffer?

    func append(_ buffer: ByteBuffer) {
        if self.buffer == nil {
            self.buffer = buffer
        } else {
            var buffer = buffer
            self.buffer!.writeBuffer(&buffer)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.append(self.unwrapInboundIn(data))
        self.decode(context: context, &self.buffer!)
    }

    func decode(context: ChannelHandlerContext, _ buffer: inout ByteBuffer) {
        while let slice = buffer.readSlice(length: 2) {
            context.fireChannelRead(self.wrapInboundOut(slice))
        }
    }
}

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
defer {
    try! group.syncShutdownGracefully()
}

let server = try ServerBootstrap(group: group)
    .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    .childChannelInitializer { channel in
        channel.pipeline.addHandlers(ProduceInboundWriteWhenAnXGetsWrittenHandler(),
                                     NaiveTwoByteFramingHandler(),
                                     EchoHandler())
    }
    .bind(to: .init(ipAddress: "127.0.0.1", port: 12345)).wait()

print("up and running on \(server.localAddress.debugDescription)")
try server.closeFuture.wait()
