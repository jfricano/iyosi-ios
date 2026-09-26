"""Regenerate the dependency-free Xcode project after adding Swift source files."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent
SOURCES = sorted((ROOT / "iYosi").glob("*.swift"))


def uid(label: str) -> str:
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()


def ref(label: str) -> str:
    return uid(label)


def block(name: str, fields: list[str]) -> str:
    return f"\t\t{ref(name)} /* {name} */ = {{\n" + "\n".join("\t\t\t" + field for field in fields) + "\n\t\t};"


objects = []
for source in SOURCES:
    name = source.name
    objects.append(block("file:" + name, ["isa = PBXFileReference;", "lastKnownFileType = sourcecode.swift;", f"path = {name};", 'sourceTree = "<group>";']))
    objects.append(block("build:" + name, ["isa = PBXBuildFile;", f"fileRef = {ref('file:' + name)} /* {name} */;"]))
objects.append(block("file:Assets", ["isa = PBXFileReference;", "lastKnownFileType = folder.assetcatalog;", "path = Assets.xcassets;", 'sourceTree = "<group>";']))
objects.append(block("build:Assets", ["isa = PBXBuildFile;", f"fileRef = {ref('file:Assets')} /* Assets.xcassets */;"]))
objects.append(block("file:Info", ["isa = PBXFileReference;", "lastKnownFileType = text.plist.xml;", "path = Info.plist;", 'sourceTree = "<group>";']))
objects.append(block("file:Product", ["isa = PBXFileReference;", "explicitFileType = wrapper.application;", "includeInIndex = 0;", "path = iYosi.app;", "sourceTree = BUILT_PRODUCTS_DIR;"]))

source_refs = " ".join(f"{ref('file:' + file.name)} /* {file.name} */," for file in SOURCES)
build_refs = " ".join(f"{ref('build:' + file.name)} /* {file.name} */," for file in SOURCES)
objects.append(block("group:root", ["isa = PBXGroup;", f"children = ({ref('group:app')} /* iYosi */, {ref('group:products')} /* Products */,);", 'sourceTree = "<group>";']))
objects.append(block("group:app", ["isa = PBXGroup;", f"children = ({source_refs} {ref('file:Assets')} /* Assets.xcassets */, {ref('file:Info')} /* Info.plist */,);", "path = iYosi;", 'sourceTree = "<group>";']))
objects.append(block("group:products", ["isa = PBXGroup;", f"children = ({ref('file:Product')} /* iYosi.app */,);", "name = Products;", 'sourceTree = "<group>";']))
objects.append(block("phase:sources", ["isa = PBXSourcesBuildPhase;", "buildActionMask = 2147483647;", f"files = ({build_refs});", "runOnlyForDeploymentPostprocessing = 0;"]))
objects.append(block("phase:resources", ["isa = PBXResourcesBuildPhase;", "buildActionMask = 2147483647;", f"files = ({ref('build:Assets')} /* Assets.xcassets */,);", "runOnlyForDeploymentPostprocessing = 0;"]))
objects.append(block("target:app", ["isa = PBXNativeTarget;", f"buildConfigurationList = {ref('configlist:target')} /* Build configuration list for PBXNativeTarget \"iYosi\" */;", f"buildPhases = ({ref('phase:sources')} /* Sources */, {ref('phase:resources')} /* Resources */,);", "buildRules = ();", "dependencies = ();", "name = iYosi;", "productName = iYosi;", f"productReference = {ref('file:Product')} /* iYosi.app */;", 'productType = "com.apple.product-type.application";']))
objects.append(block("project", ["isa = PBXProject;", "attributes = { LastUpgradeCheck = 1600; TargetAttributes = { " + ref("target:app") + " = { CreatedOnToolsVersion = 16.0; ProvisioningStyle = Automatic; }; }; };", f"buildConfigurationList = {ref('configlist:project')} /* Build configuration list for PBXProject \"iYosi\" */;", 'compatibilityVersion = "Xcode 15.0";', "developmentRegion = en;", "hasScannedForEncodings = 0;", "knownRegions = (en, Base,);", f"mainGroup = {ref('group:root')} /* Main group */;", f"productRefGroup = {ref('group:products')} /* Products */;", 'projectDirPath = "";', 'projectRoot = "";', f"targets = ({ref('target:app')} /* iYosi */,);"]))

for level in ("Debug", "Release"):
    project_settings = ["ALWAYS_SEARCH_USER_PATHS = NO;", "CLANG_ENABLE_MODULES = YES;", "IPHONEOS_DEPLOYMENT_TARGET = 17.0;", "SDKROOT = iphoneos;", "SWIFT_VERSION = 5.9;"]
    if level == "Debug":
        project_settings += ["DEBUG_INFORMATION_FORMAT = dwarf;", "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;"]
    else:
        project_settings += ["DEBUG_INFORMATION_FORMAT = dwarf-with-dsym;", "SWIFT_COMPILATION_MODE = wholemodule;"]
    objects.append(block(f"config:project:{level}", ["isa = XCBuildConfiguration;", "buildSettings = { " + " ".join(project_settings) + " };", f"name = {level};"]))
    target_settings = ["ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", "CODE_SIGN_STYLE = Automatic;", "CURRENT_PROJECT_VERSION = 1;", "GENERATE_INFOPLIST_FILE = NO;", "INFOPLIST_FILE = iYosi/Info.plist;", "IPHONEOS_DEPLOYMENT_TARGET = 17.0;", "MARKETING_VERSION = 1.0;", "PRODUCT_BUNDLE_IDENTIFIER = com.orcasolutions.iyosi;", 'PRODUCT_NAME = "$(TARGET_NAME)";', 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";', 'TARGETED_DEVICE_FAMILY = "1,2";', "SWIFT_VERSION = 5.9;"]
    objects.append(block(f"config:target:{level}", ["isa = XCBuildConfiguration;", "buildSettings = { " + " ".join(target_settings) + " };", f"name = {level};"]))
objects.append(block("configlist:project", ["isa = XCConfigurationList;", f"buildConfigurations = ({ref('config:project:Debug')} /* Debug */, {ref('config:project:Release')} /* Release */,);", "defaultConfigurationIsVisible = 0;", "defaultConfigurationName = Release;"]))
objects.append(block("configlist:target", ["isa = XCConfigurationList;", f"buildConfigurations = ({ref('config:target:Debug')} /* Debug */, {ref('config:target:Release')} /* Release */,);", "defaultConfigurationIsVisible = 0;", "defaultConfigurationName = Release;"]))

project = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 60;\n\tobjects = {\n" + "\n".join(objects) + "\n\t};\n\trootObject = " + ref("project") + " /* Project object */;\n}\n"
destination = ROOT / "iYosi.xcodeproj" / "project.pbxproj"
destination.parent.mkdir(exist_ok=True)
destination.write_text(project)
print(destination)
