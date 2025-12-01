# Kernel Configuration for ImageHarden

The `image_harden` system relies on several modern Linux kernel security features to provide robust sandboxing. If you are compiling your own kernel, you must ensure that these features are enabled. This guide provides the necessary `Kconfig` options and a sample workflow for configuring a kernel to support `image_harden`.

## Required Kernel Features

`image_harden`'s sandboxing relies on three key kernel features:

1.  **`seccomp` and `seccomp-bpf`**: For syscall filtering.
2.  **Kernel Namespaces**: For process isolation.
3.  **Landlock LSM**: For filesystem sandboxing.

## Kernel Configuration Options

To ensure these features are available, you must enable the following options in your kernel configuration (`.config` file).

### General Security Options

```
CONFIG_SECURITY=y
CONFIG_SECURITYFS=y
```

### `seccomp-bpf`

`seccomp` and its more powerful `bpf`-based filter mode are essential for restricting the system calls available to the sandboxed process.

```
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
```

### Kernel Namespaces

Namespaces are critical for isolating the decoding process from the rest of the system. `image_harden` specifically uses the PID, network, and mount namespaces.

```
CONFIG_NAMESPACES=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_MNT_NS=y
```

### Landlock LSM

Landlock provides the fine-grained filesystem sandboxing used to restrict file access to only the media file being processed.

```
CONFIG_SECURITY_LANDLOCK=y
```

## Sample Kernel Configuration Workflow

Here is a sample workflow for configuring a kernel to support `image_harden`. This assumes you have already downloaded the kernel source code and are in the root directory of the kernel source tree.

1.  **Generate a default configuration:**

    ```bash
    make defconfig
    ```

2.  **Open the kernel configuration menu:**

    ```bash
    make menuconfig
    ```

3.  **Enable the required options:**

    *   **`seccomp-bpf`**:
        *   Go to `General setup` -> `Namespaces support` and enable all the required namespaces.
        *   Go to `Enable loadable module support` and ensure it is enabled.
        *   Go to `Security options` and enable `Enable seccomp to safely compute untrusted bytecode`.

    *   **Landlock LSM**:
        *   Go to `Security options` -> `Security framework`.
        *   Enable `Enable different security models`.
        *   Select `Landlock`.

4.  **Save the configuration and exit.**

5.  **Build the kernel:**

    ```bash
    make -j"$(nproc)"
    ```

By ensuring these options are enabled in your kernel build, you can be confident that `image_harden` will have all the necessary tools to provide a secure, sandboxed environment for media decoding.
