#!/usr/bin/env bash

# ------------------------------------------
# Maven Dependency Decompiler and Attacher
# ------------------------------------------
# This script decompiles all Maven dependencies for an IntelliJ IDEA project
# and attaches the decompiled sources in the IDE's project configuration.
#
# Usage: Run this script in the project's root directory (where the pom.xml is).
#        Ensure the FERNFLOWER_JAR path is correct and you have write access to .idea and ~/.m2.
#
# Requirements:
#   - Maven installed (to list dependencies).
#   - Java installed (to run FernFlower decompiler).
#   - IntelliJ IDEA’s FernFlower (java-decompiler.jar) available.
#   - 'unzip' command available for extracting jars.


set -e

# 0) Find IntelliJ and FernFlower
IDEA_APP=$(find /Applications ~/Applications -maxdepth 2 -type d -name 'IntelliJ IDEA*.app' 2>/dev/null | head -n1)
if [[ -z "$IDEA_APP" ]]; then
  echo "❗ IntelliJ IDEA.app not found in /Applications or ~/Applications"
  exit 1
fi
INTELLIJ_INSTALL_DIR="$IDEA_APP/Contents"
FERNFLOWER_JAR="$INTELLIJ_INSTALL_DIR/plugins/java-decompiler/lib/java-decompiler.jar"
if [[ ! -f "$FERNFLOWER_JAR" ]]; then
  echo "❗ Cannot find fernflower jar at $FERNFLOWER_JAR"
  exit 1
fi

# 2. Use Maven to get the classpath of all compile+runtime dependencies (as a single line of jar paths)
echo "Running Maven to get project classpath..."
mvn dependency:build-classpath -Dmdep.outputFile=target/cp.txt >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "Error: Maven failed to build classpath. Make sure you have a pom.xml and Maven is installed." >&2
  exit 1
fi

CP_FILE="target/cp.txt"
if [[ ! -f "$CP_FILE" ]]; then
  echo "Error: Maven did not produce the classpath file $CP_FILE." >&2
  exit 1
fi

# Read the classpath file (it contains a long classpath string)
CLASSPATH=$(< "$CP_FILE")
# Split classpath into an array of JAR paths (assuming ':' is the separator on this OS)
IFS=':' read -r -a JAR_PATHS <<< "$CLASSPATH"

# 3. Prepare a list of JARs to decompile (skip those already decompiled or with sources attached)
TO_DECOMPILE=()
for JAR in "${JAR_PATHS[@]}"; do
  # Only consider actual .jar files inside the local Maven repo
  if [[ "$JAR" == *".m2/repository/"* && "$JAR" == *.jar ]]; then
    JAR_DIR=$(dirname "$JAR")
    FF_SRC_DIR="$JAR_DIR/fernflower-sources"
    # Check if this dependency already has either an official sources jar or a fernflower folder
    if [[ -d "$FF_SRC_DIR" ]]; then
      echo "[SKIP] Already decompiled: $(basename "$JAR")"
    else
      # If an official sources.jar exists, we can skip decompiling (IntelliJ can use it if attached)
      # Alternatively, you may still decompile to have the exact bytecode version.
      if [[ -f "${JAR%.jar}-sources.jar" ]]; then
        echo "[SKIP] Sources JAR exists for: $(basename "$JAR")"
        # (We will attach the official sources jar later if present)
      else
        TO_DECOMPILE+=("$JAR")
      fi
    fi
  fi
done

# 4. Decompile JARs in parallel
CPU_COUNT=$(grep -c processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
MAX_PROCS=$(( CPU_COUNT > 1 ? CPU_COUNT : 1 ))  # number of parallel jobs (at least 1)
echo "Starting decompilation of ${#TO_DECOMPILE[@]} JARs using $MAX_PROCS parallel threads..."
# Function to decompile one jar (to run in background)
# 3) Cache-aware decompile function
#    For each JAR, we compute:
#      real JAR path in ~/.m2/repository → artifactDir
#      cache dir = artifactDir/fernflower-sources
#    If cache exists, SKIP; otherwise decompile INTO cache.
decompile_and_cache(){
  local jarpath="$1"
  local artifact=$(basename "$jarpath")
  # Locate actual JAR in ~/.m2
  local real=$(find "$HOME/.m2/repository" -type f -name "$artifact" | head -n1)
  local artifactDir=${real%/*}
  local cache_dir="$artifactDir/fernflower-sources"

  if [[ -d "$cache_dir" ]]; then
    echo "✔  [CACHE HIT] $artifact"
  else
    echo "⟳  [CACHE MISS] Decompiling $artifact → $cache_dir"
    mkdir -p "$cache_dir"
    # Run FernFlower to produce a source-JAR inside cache_dir
    java -cp "$FERNFLOWER_JAR" \
      org.jetbrains.java.decompiler.main.decompiler.ConsoleDecompiler \
      -hdc=0 -dgs=1 -rsy=1 "$jarpath" "$cache_dir"
    # The decompiler outputs artifact.jar inside cache_dir; extract it
    unzip -q "$cache_dir/$artifact" -d "$cache_dir"
    rm -f "$cache_dir/$artifact"
  fi
}

export -f decompile_and_cache
export FERNFLOWER_JAR  # export env for subshells to use

# Run decompile jobs in parallel
if [[ ${#TO_DECOMPILE[@]} -gt 0 ]]; then
  # Using xargs to parallelize
  printf "%s\n" "${TO_DECOMPILE[@]}" | xargs -P $MAX_PROCS -I{} bash -c 'decompile_and_cache "$@"' _ {}
else
  echo "No JARs need decompilation."
fi

#-------------------------------------------------------------------------------
# 4) Package each fernflower-sources folder into a -sources.jar
#-------------------------------------------------------------------------------
echo "📦 Packaging sources jars..."
for jardir in $(find "$HOME/.m2/repository" -type d -name 'fernflower-sources'); do
  basepath=$(dirname "$jardir")                        # artifact version folder
  artifact=$(basename "$basepath")
  group=$(dirname "$basepath" | sed "s|.*/repository/||" | sed 's#/[^/]*$##')
  name=$(basename "$jardir")                           # fernflower-sources
  # deduce jar base name from folder contents
  version_dir="$basepath"                            # .../artifactId/version
  version=$(basename "$version_dir")
  artifact_dir=$(dirname "$version_dir")             # .../artifactId
  artifactId=$(basename "$artifact_dir")             # e.g. communication

  jarname="${artifactId}-${version}-sources.jar"
  srcjar="$version_dir/$jarname"

  if [[ -f "$srcjar" ]]; then
    echo "  ✔ Exists: $srcjar"
    continue
  fi

  ( cd "$jardir" && jar cf "$srcjar" . )
  echo "  ✓ Created: $srcjar"
done

echo "✅ All done. Reload your Maven project in IntelliJ to auto-attach the new *-sources.jar files."