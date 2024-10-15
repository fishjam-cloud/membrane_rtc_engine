FROM membraneframeworklabs/docker_membrane:v2.3.0

WORKDIR /engine
COPY engine/lib lib/
COPY engine/mix.exs engine/mix.lock ./
ENV RTC_ENGINE_PATH=/engine

WORKDIR /webrtc
COPY webrtc/config config/
COPY webrtc/lib lib/
COPY webrtc/mix.exs webrtc/mix.lock ./

ARG APP_PATH=webrtc/integration_test/test_videoroom
ENV MIX_ENV=test

WORKDIR /app
COPY ${APP_PATH}/mix.exs ${APP_PATH}/mix.lock ./
RUN mix deps.get --only $MIX_ENV

COPY ${APP_PATH}/config/config.exs ${APP_PATH}/config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY ${APP_PATH}/lib lib/
RUN mix compile

COPY ${APP_PATH}/test test/

COPY ${APP_PATH}/config/runtime.exs config/

COPY ${APP_PATH}/assets assets/
RUN cd assets && npm install
RUN mix assets.deploy
RUN mix playwright.install

# Generate self-signed cert for SSL
RUN mix phx.gen.cert

CMD ["mix", "test"]
