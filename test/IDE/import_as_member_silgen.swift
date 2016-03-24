// RUN: %target-swift-frontend -emit-sil -I %S/Inputs/custom-modules %s 2>&1 | FileCheck --check-prefix=SIL %s
import ImportAsMember
import ImportAsMember.Proto

public func returnGlobalVar() -> Double {
	return Struct1.globalVar
}
// SIL-LABEL: sil {{.*}}returnGlobalVar{{.*}} () -> Double {
// SIL:   %0 = global_addr @IAMStruct1GlobalVar : $*Double
// SIL:   %2 = load %0 : $*Double
// SIL:   return %2 : $Double
// SIL-NEXT: }

// SIL-LABEL: sil {{.*}}useProto{{.*}} (@owned IAMProto) -> () {
// TODO: Move this test case into test/SILGen, then add in body checks
public func useProto(p: IAMProto) {
	p.mutateSomeState()
	let v = p.someValue
	p.someValue = v+1
}

// SIL-LABEL: sil {{.*}}anchor{{.*}} () -> () {
func anchor() {}
