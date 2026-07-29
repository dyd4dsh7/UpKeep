import Darwin
import Testing
@testable import Upkeep

@Test func appManagementPermissionMapsMacOSAccessErrorsToDenied() {
    #expect(AppManagementPermissionChecker.status(forErrno: EPERM) == .denied)
    #expect(AppManagementPermissionChecker.status(forErrno: EACCES) == .denied)
}

@Test func appManagementPermissionDoesNotCallUnrelatedFailuresDenied() {
    #expect(AppManagementPermissionChecker.status(forErrno: ENOENT) == .unavailable)
    #expect(AppManagementPermissionChecker.status(forErrno: EIO) == .unavailable)
}
