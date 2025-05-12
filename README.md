# Maven Dependency Source Explorer

> **Note:** This script is specifically designed and tested on macOS environments.

This repository provides a shell script to decompile all Maven dependencies in your project, generate `-sources.jar` files, and attach them to IntelliJ IDEA. It is especially useful when you need to browse implementation details inside closed-source libraries.

Working with closed-source JARs can be a major headache: without public sources, you’re forced to rely solely on bytecode inspection and incomplete Javadocs, making debugging and understanding library internals time-consuming and error-prone. This tool streamlines that process by giving you full, decompiled source access in your IDE.

## Features

* Automatically build your project classpath via Maven.
* Decompile `.jar` dependencies in parallel using IntelliJ’s embedded FernFlower decompiler.
* Cache existing decompiled sources to speed up subsequent runs.
* Produce `artifactId-version-sources.jar` files for each dependency.
* Attach resulting source jars in IntelliJ via project libraries.

## Prerequisites

* **macOS 10.14+** (Mojave, Catalina, Big Sur, Monterey, Ventura)

* Java 8 or higher installed.

* Maven installed and available on your `PATH`.

* IntelliJ IDEA (Community or Ultimate).

* Access to the FernFlower jar shipped with IntelliJ (usually under `IntelliJ IDEA.app/Contents/plugins/java-decompiler/fernflower.jar`).

## Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/tungpv98/maven-dependency-source-explorer.git   cd maven-decompile-sources
   ```
2. Make sure the script is executable:

   ```bash
   chmod +x decompile-deps.sh
   ```
3. Point the script at your IntelliJ FernFlower jar (if not autodetected):

   ```bash
   export FERNFLOWER=/path/to/fernflower.jar
   ```

## Usage

Run the script from **any** Maven-based project root to decompile its dependencies:

```bash
/path/to/maven-decompile-sources/decompile-deps.sh
```

By default, it will:

1. Generate a temporary POM to collect your project’s classpath.
2. Decompile each dependency under `~/.m2/repository/.../fernflower-sources`.
3. Package each decompiled folder into `artifactId-version-sources.jar` alongside the original `.jar`.

### Quick Start in Your Project

To quickly enable searching inside library code in any Maven project:

1. **Create the script file**

    * Copy `decompile-deps.sh` from this repo into the root of the project where you want to search.

2. **Make it executable**

   ```bash
   chmod +x decompile-deps.sh
   ```

3. **(Optional) Set FernFlower path**

   ```bash
   export FERNFLOWER=/path/to/fernflower.jar
   ```

4. **Run the decompiler**

   ```bash
   ./decompile-deps.sh
   ```

5. **Reload Maven in IntelliJ**

    * In IntelliJ IDEA, right-click the project’s root `pom.xml` and select **"Reload Maven Project"**.

6. **Search decompiled sources**

    * Press **Shift** twice to open the "Search Everywhere" dialog, then type any class or method name to jump into the decompiled code.

## Troubleshooting## Troubleshooting

* **Missing dependencies**: Run `mvn dependency:resolve` first to populate your local repo.

