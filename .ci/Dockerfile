# SPDX-License-Identifier: MPL-2.0
#
# Build environment for the Linux-testable half of pocket-nutrition-ios.
#
# WHAT THIS CAN AND CANNOT BUILD
# It builds and tests PocketNutritionCore — the behavioural contract shared with the web client and
# Android. It cannot build the app: SwiftUI, UIKit and the iOS SDK are Apple-only and are not licensed
# for Linux. The app target is archived on a Mac, by hand.
#
# That split is the point rather than a compromise. The rules that must not drift between three
# clients are the ones a container can verify on every push; the UI is the part a person looks at
# anyway. Adding an Apple-only import to PocketNutritionCore silently removes it from CI, which is why
# Package.swift says so too.
#
# Built and pushed by .gitea/workflows/ci-image.yml, only when this file changes.

# Pinned to the exact toolchain the package was developed against — Apple Swift 6.3.3 — so that a CI
# result and a local result mean the same thing. An unpinned image is a build that changes under you.
#
# The floor is 6.2, not 6.0: Package.swift uses `treatAllWarnings(as: .error)`, introduced in
# PackageDescription 6.2, and under an older toolchain the manifest does not parse at all.
FROM swift:6.3.3-noble

ENV DEBIAN_FRONTEND=noninteractive

# NODE IS NOT OPTIONAL, even though nothing in this project is JavaScript.
#
# Gitea Actions runs JavaScript actions — actions/checkout@v4 and friends — *inside* the job container,
# using a `node` binary it expects to find there. Without it every container job dies at checkout with:
#
#     exec: "node": executable file not found in $PATH   (exit 127)
#
# which reads like a broken workflow rather than a missing runtime. This cost a CI run in the android
# repo before it was understood; the trap applies to every image used as a job container.
#
# Installed from the official tarball at a pinned version rather than by piping a remote setup script
# into a shell, with the architecture derived from dpkg so the image stays buildable on amd64 and arm64.
ARG NODE_VERSION=24.18.0
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && ARCH="$(dpkg --print-architecture)" \
    && case "${ARCH}" in \
         amd64) NODE_ARCH=x64 ;; \
         arm64) NODE_ARCH=arm64 ;; \
         *) echo "unsupported architecture ${ARCH}" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/node.tar.xz \
        "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
        --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md \
    && rm /tmp/node.tar.xz

# Fail the image build rather than the first pipeline run if something did not land.
#
# The Foundation probe is deliberate. The corpus reader depends on JSONSerialization from
# swift-corelibs-foundation, a different implementation from Apple's, and integer-valued JSON numbers
# are precisely where the two differ — which is why the reader coerces numbers by hand instead of
# casting. Proving the probe parses here means a failure in CI is about the corpus, not the runtime.
RUN set -eux; \
    swift --version; \
    node --version; \
    git --version; \
    printf 'import Foundation\nlet o = try JSONSerialization.jsonObject(with: Data("{\\"v\\":64}".utf8)) as! [String: Any]\nprint("probe v=", (o["v"] as? NSNumber)?.doubleValue ?? -1)\n' > /tmp/probe.swift; \
    swift /tmp/probe.swift; \
    rm -f /tmp/probe.swift; \
    echo "ci-swift ready: $(swift --version | head -1), Node ${NODE_VERSION}"
