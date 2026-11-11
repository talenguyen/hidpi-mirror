#ifndef CVIRTUALDISPLAY_H
#define CVIRTUALDISPLAY_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

/// Creates a virtual display with a single HiDPI mode.
/// `pointsW` x `pointsH` is the "looks like" size; the backing store is 2x.
/// Returns an opaque retained handle (release with dh_vd_destroy) or NULL.
void *dh_vd_create(const char *name, uint32_t pointsW, uint32_t pointsH, double hz,
                   uint32_t vendorID, uint32_t productID, uint32_t serial,
                   CGDirectDisplayID *outDisplayID);

/// Releases the handle; the virtual display disappears.
void dh_vd_destroy(void *handle);

#endif
