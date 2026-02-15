FROM golang:1.26-alpine AS build

RUN apk add --no-cache git

RUN git clone https://github.com/fcambus/rrda.git /src/rrda

WORKDIR /src/rrda

RUN go build -o /rrda

FROM alpine:3.21

RUN apk add --no-cache ca-certificates

COPY --from=build /rrda /usr/local/bin/rrda

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/rrda", "-host", "0.0.0.0"]
