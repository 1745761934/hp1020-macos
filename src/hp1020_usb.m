// HP LaserJet 1020 firmware uploader / raw data sender for modern macOS.
// No libusb, no Homebrew: matches IOUSBHostInterface by registry idVendor/idProduct.
//
//   hp1020_usb FILE          upload sihp1020.dl unless the printer already reports ;FWVER:
//   hp1020_usb --send FILE   always transmit FILE to the bulk OUT endpoint
//   hp1020_usb --info        report device ID and firmware state
//
// Note: a reported FWVER does not by itself mean the firmware is running.
// Only FWVER:20080222 is the known-good build; older images (20050309,
// 20041129) are accepted by the printer but never render. `--info` therefore
// also prints fwver_ok= yes|no so callers can gate on the exact build.

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/usb/IOUSBLib.h>

#define MAX_RETRIES 3
#define HP_VID 0x03f0
#define HP_PID 0x2b17

static io_service_t findPrinterInterface(void) {
    CFMutableDictionaryRef md = IOServiceMatching("IOUSBHostInterface");
    if (!md) return 0;
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, md, &it) != KERN_SUCCESS) return 0;
    io_service_t hit = 0, s;
    while ((s = IOIteratorNext(it))) {
        int v = 0, p = 0;
        CFTypeRef vr = IORegistryEntryCreateCFProperty(s, CFSTR("idVendor"), NULL, 0);
        CFTypeRef pr = IORegistryEntryCreateCFProperty(s, CFSTR("idProduct"), NULL, 0);
        if (vr) { CFNumberGetValue(vr, kCFNumberSInt32Type, &v); CFRelease(vr); }
        if (pr) { CFNumberGetValue(pr, kCFNumberSInt32Type, &p); CFRelease(pr); }
        if (v == HP_VID && p == HP_PID && !hit) hit = s;
        else IOObjectRelease(s);
    }
    IOObjectRelease(it);
    return hit;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL forceSend = NO, infoOnly = NO;
        const char *path = NULL;

        if (argc == 3 && strcmp(argv[1], "--send") == 0) { forceSend = YES; path = argv[2]; }
        else if (argc == 2 && strcmp(argv[1], "--info") == 0) { infoOnly = YES; }
        else if (argc == 2 && argv[1][0] != '-') { path = argv[1]; }
        else { fprintf(stderr, "usage: %s [--send|--info] FILE\n", argv[0]); return 2; }

        io_service_t svc = findPrinterInterface();
        if (!svc) {
            fprintf(stderr, "HP LaserJet 1020 (03f0:2b17) not found on USB\n");
            return 1;
        }

        IOCFPlugInInterface **plug = NULL;
        SInt32 score = 0;
        if (IOCreatePlugInInterfaceForService(svc, kIOUSBInterfaceUserClientTypeID,
                kIOCFPlugInInterfaceID, &plug, &score) != KERN_SUCCESS || !plug) {
            fprintf(stderr, "cannot create plugin interface\n");
            IOObjectRelease(svc);
            return 1;
        }
        IOObjectRelease(svc);

        IOUSBInterfaceInterface **itf = NULL;
        HRESULT hr = (*plug)->QueryInterface(plug,
                        CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID500),
                        (LPVOID *)&itf);
        (*plug)->Release(plug);
        if (hr || !itf) { fprintf(stderr, "QueryInterface failed\n"); return 1; }

        UInt8 ifNum = 0, nEp = 0;
        (*itf)->GetInterfaceNumber(itf, &ifNum);
        (*itf)->GetNumEndpoints(itf, &nEp);

        // endpoint 0x01 is the bulk OUT for this printer class
        UInt8 outEp = 1;
        IOReturn or = (*itf)->USBInterfaceOpen(itf);
        if (or != kIOReturnSuccess) {
            fprintf(stderr, "USBInterfaceOpen: 0x%08x (device busy?)\n", (unsigned)or);
            return 1;
        }
        usleep(100000);

        // ---- IEEE-1284 device ID ----
        UInt8 id[512] = {0};
        IOUSBDevRequest ctl;
        memset(&ctl, 0, sizeof ctl);
        ctl.bmRequestType = USBmakebmRequestType(kUSBIn, kUSBClass, kUSBInterface);
        ctl.bRequest = 0; ctl.wValue = 0; ctl.wIndex = ifNum;
        ctl.wLength = sizeof id; ctl.pData = id;
        IOReturn ir = (*itf)->ControlRequest(itf, 0, &ctl);
        BOOL hasFw = NO, fwOk = NO;
        if (ir == kIOReturnSuccess && ctl.wLenDone >= 2) {
            int len = (id[0] << 8) | id[1];
            if (len > (int)ctl.wLenDone) len = (int)ctl.wLenDone;
            if (len > 2) {
                id[len < 511 ? len : 511] = 0;
                printf("Device ID: %s\n", (char *)id + 2);
                if (memmem(id + 2, (size_t)(len - 2), ";FWVER:", 7)) hasFw = YES;
                if (memmem(id + 2, (size_t)(len - 2), ";FWVER:20080222;", 16)) fwOk = YES;
            }
        } else {
            printf("Device ID query returned 0x%08x\n", (unsigned)ir);
        }

        if (infoOnly) {
            printf("firmware_loaded=%s\n", hasFw ? "yes" : "no");
            printf("fwver_ok=%s\n", fwOk ? "yes" : "no");
            (*itf)->USBInterfaceClose(itf);
            (*itf)->Release(itf);
            return 0;
        }
        if (!forceSend && fwOk) {
            printf("Firmware already loaded.\n");
            (*itf)->USBInterfaceClose(itf);
            (*itf)->Release(itf);
            return 0;
        }

        FILE *f = fopen(path, "rb");
        if (!f) { perror(path); return 1; }
        const size_t CHUNK = 16384;
        UInt8 *buf = malloc(CHUNK);
        size_t n; unsigned long total = 0;
        while ((n = fread(buf, 1, CHUNK, f)) > 0) {
            size_t off = 0;
            int retries = 0;
            while (off < n) {
                IOReturn w = (*itf)->WritePipeTO(itf, outEp,
                                buf + off, (UInt32)(n - off), 30000, 30000);
                if (w == kIOReturnSuccess) {
                    off = n;                 // 整块已送出
                    retries = 0;
                } else if (w == kIOUSBPipeStalled) {
                    // 端点停摆：清除后从当前位置继续，不会重复已发数据
                    (*itf)->ClearPipeStall(itf, outEp);
                    if (++retries > MAX_RETRIES) {
                        fprintf(stderr, "USB pipe stalled repeatedly at %lu\n",
                                total + off);
                        free(buf); fclose(f);
                        (*itf)->USBInterfaceClose(itf);
                        (*itf)->Release(itf);
                        return 1;
                    }
                    usleep(50000);
                } else if (w == kIOReturnTimeout) {
                    // 关键：超时不等于没送到。USB bulk OUT 超时后，
                    // 数据往往已经进入打印机缓冲。若在这里整块重发，
                    // 打印机就会把同一段内容收两次 —— 这正是重复打印的成因。
                    // 因此超时直接判为失败，绝不自动重发。
                    fprintf(stderr,
                            "USB write timed out at %lu — aborting without retry\n"
                            "  (retrying would duplicate content on the page)\n",
                            total + off);
                    free(buf); fclose(f);
                    (*itf)->USBInterfaceClose(itf);
                    (*itf)->Release(itf);
                    return 2;
                } else {
                    fprintf(stderr, "USB write error 0x%08x at %lu\n",
                            (unsigned)w, total + off);
                    free(buf); fclose(f);
                    (*itf)->USBInterfaceClose(itf);
                    (*itf)->Release(itf);
                    return 1;
                }
            }
            total += n;
        }
        free(buf); fclose(f);
        printf(forceSend ? "Print data sent (%lu bytes).\n" : "Firmware sent (%lu bytes).\n", total);

        (*itf)->USBInterfaceClose(itf);
        (*itf)->Release(itf);
        if (!forceSend) sleep(8);
        return 0;
    }
}
