#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>

#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm_fourcc.h>

#define DEFAULT_OUTPUT "screenshot.bmp"

#pragma pack(push, 1)
typedef struct {
	uint16_t type;
	uint32_t size;
	uint16_t reserved1;
	uint16_t reserved2;
	uint32_t offset;
} BMPFileHeader;

typedef struct {
	uint32_t size;
	int32_t  width;
	int32_t  height;
	uint16_t planes;
	uint16_t bits_per_pixel;
	uint32_t compression;
	uint32_t image_size;
	int32_t  x_ppm;
	int32_t  y_ppm;
	uint32_t colors_used;
	uint32_t colors_important;
} BMPInfoHeader;
#pragma pack(pop)

struct fb_info {
	uint32_t width;
	uint32_t height;
	uint32_t pitch;
	uint32_t handle;
	uint32_t bpp;
	uint32_t drm_format;
	int handle_from_getfb;
};

static uint32_t drm_format_to_bpp(uint32_t format) {
	switch (format) {
	case DRM_FORMAT_XRGB8888:
	case DRM_FORMAT_ARGB8888:
	case DRM_FORMAT_XBGR8888:
	case DRM_FORMAT_ABGR8888:
		return 32;
	case DRM_FORMAT_RGB565:
	case DRM_FORMAT_BGR565:
		return 16;
	case DRM_FORMAT_XRGB2101010:
	case DRM_FORMAT_XBGR2101010:
		return 30;
	default:
		return 32;
	}
}

static void destroy_dumb(int fd, uint32_t handle) {
	struct drm_mode_destroy_dumb arg;

	memset(&arg, 0, sizeof(arg));
	arg.handle = handle;
	drmIoctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &arg);
}

static void *map_fb(int fd, uint32_t handle, size_t size, int *prime_fd_out) {
	struct drm_prime_handle arg;
	void *ptr;

	memset(&arg, 0, sizeof(arg));
	arg.handle = handle;

	if (drmIoctl(fd, DRM_IOCTL_PRIME_HANDLE_TO_FD, &arg)) {
		fprintf(stderr, "DRM_IOCTL_PRIME_HANDLE_TO_FD failed: %s\n",
			strerror(errno));
		return NULL;
	}

	ptr = mmap(0, size, PROT_READ, MAP_SHARED, arg.fd, 0);
	if (ptr == MAP_FAILED) {
		fprintf(stderr, "mmap failed: %s\n", strerror(errno));
		close(arg.fd);
		return NULL;
	}

	if (prime_fd_out)
		*prime_fd_out = arg.fd;
	else
		close(arg.fd);

	return ptr;
}

static int get_crtc_fb(int fd, uint32_t crtc_id, struct fb_info *info) {
	drmModeCrtcPtr crtc;
	int ret = -1;

	crtc = drmModeGetCrtc(fd, crtc_id);
	if (!crtc) {
		fprintf(stderr, "Unknown CRTC %d\n", crtc_id);
		return -1;
	}

	if (crtc->mode_valid && crtc->buffer_id > 0) {
		info->width = crtc->width;
		info->height = crtc->height;
		info->pitch = crtc->mode.hdisplay;
		ret = crtc->buffer_id;
	}

	drmModeFreeCrtc(crtc);
	return ret;
}

static int get_encoder_fb(int fd, uint32_t encoder_id, struct fb_info *info) {
	drmModeEncoderPtr encoder;
	int id;

	encoder = drmModeGetEncoder(fd, encoder_id);
	if (!encoder) {
		fprintf(stderr, "Unknown Encoder %d\n", encoder_id);
		return -1;
	}

	id = get_crtc_fb(fd, encoder->crtc_id, info);

	drmModeFreeEncoder(encoder);
	return id;
}

static int get_connector_fb(int fd, uint32_t connector_id, struct fb_info *info) {
	drmModeConnector *connector;
	int id;

	connector = drmModeGetConnector(fd, connector_id);
	if (!connector) {
		fprintf(stderr, "Unknown Connector %d\n", connector_id);
		return -1;
	}

	id = get_encoder_fb(fd, connector->encoder_id, info);

	drmModeFreeConnector(connector);
	return id;
}

static int get_plane_fb(int fd, uint32_t plane_id, struct fb_info *info) {
	drmModePlanePtr plane;
	int id;

	plane = drmModeGetPlane(fd, plane_id);
	if (!plane) {
		fprintf(stderr, "Unknown Plane %d\n", plane_id);
		return -1;
	}

	id = plane->fb_id;

	drmModeFreePlane(plane);
	return id;
}

static int get_default_fb(int fd, struct fb_info *info) {
	drmModeCrtcPtr crtc;
	drmModeResPtr res;
	int i, fb_id = 0;

	res = drmModeGetResources(fd);
	if (!res) {
		fprintf(stderr, "drmModeGetResources failed\n");
		return -1;
	}

	for (i = 0; i < res->count_crtcs; i++) {
		crtc = drmModeGetCrtc(fd, res->crtcs[i]);
		if (crtc && crtc->mode_valid && crtc->buffer_id > 0) {
			if (!fb_id) {
				fb_id = crtc->buffer_id;
				info->width = crtc->width;
				info->height = crtc->height;
				info->pitch = crtc->mode.hdisplay;
			}
		}
		drmModeFreeCrtc(crtc);
	}
	drmModeFreeResources(res);

	return fb_id;
}

static int get_fb_info(int fd, uint32_t fb_id, struct fb_info *info) {
	drmModeFBPtr fb;
	drmModeFB2Ptr fb2;
	uint32_t bpp;

	fb2 = drmModeGetFB2(fd, fb_id);
	if (fb2) {
		info->width = fb2->width;
		info->height = fb2->height;
		info->handle = fb2->handles[0];
		info->pitch = fb2->pitches[0];
		info->drm_format = fb2->pixel_format;
		info->bpp = drm_format_to_bpp(fb2->pixel_format);
		info->handle_from_getfb = 1;
		drmModeFreeFB2(fb2);
		return 0;
	}

	fb = drmModeGetFB(fd, fb_id);
	if (!fb) {
		fprintf(stderr, "Failed to get framebuffer %d\n", fb_id);
		return -1;
	}

	info->width = fb->width;
	info->height = fb->height;
	info->handle = fb->handle;
	info->pitch = fb->pitch;
	info->bpp = fb->bpp;
	info->handle_from_getfb = 1;
	info->drm_format = (fb->bpp == 32) ? DRM_FORMAT_XRGB8888 :
			   (fb->bpp == 16) ? DRM_FORMAT_RGB565 :
			   DRM_FORMAT_XRGB8888;

	drmModeFreeFB(fb);
	return 0;
}

static int save_bmp(const char *filename, const void *data,
		    const struct fb_info *info) {
	BMPFileHeader file_hdr;
	BMPInfoHeader info_hdr;
	FILE *fp;
	uint32_t row_size;
	uint32_t pixel_data_size;
	int padding;
	int ret = 0;

	fp = fopen(filename, "wb");
	if (!fp) {
		fprintf(stderr, "Failed to open %s: %s\n",
			filename, strerror(errno));
		return -1;
	}

	padding = (4 - (info->width * (info->bpp / 8)) % 4) % 4;
	row_size = info->width * (info->bpp / 8) + padding;
	pixel_data_size = row_size * info->height;

	memset(&file_hdr, 0, sizeof(file_hdr));
	file_hdr.type = 0x4D42;
	file_hdr.size = sizeof(BMPFileHeader) + sizeof(BMPInfoHeader) +
			pixel_data_size;
	file_hdr.offset = sizeof(BMPFileHeader) + sizeof(BMPInfoHeader);

	memset(&info_hdr, 0, sizeof(info_hdr));
	info_hdr.size = sizeof(BMPInfoHeader);
	info_hdr.width = info->width;
	info_hdr.height = info->height;
	info_hdr.planes = 1;
	info_hdr.bits_per_pixel = info->bpp;
	info_hdr.compression = 0;
	info_hdr.image_size = pixel_data_size;
	info_hdr.x_ppm = 2835;
	info_hdr.y_ppm = 2835;

	fwrite(&file_hdr, sizeof(file_hdr), 1, fp);
	fwrite(&info_hdr, sizeof(info_hdr), 1, fp);

	const uint8_t *src = (const uint8_t *)data;

	for (int y = info->height - 1; y >= 0; y--) {
		const uint8_t *row = src + (size_t)y * info->pitch;

		if (info->bpp == 32) {
			for (uint32_t x = 0; x < info->width; x++) {
				uint8_t pixel[4];
				memcpy(pixel, row + x * 4, 4);

				uint8_t bgra[4] = { pixel[0], pixel[1],
						    pixel[2], pixel[3] };
				fwrite(bgra, 1, 4, fp);
			}
		} else if (info->bpp == 16) {
			for (uint32_t x = 0; x < info->width; x++) {
				uint16_t pixel;
				memcpy(&pixel, row + x * 2, 2);

				uint8_t r5 = (pixel >> 11) & 0x1F;
				uint8_t g6 = (pixel >> 5) & 0x3F;
				uint8_t b5 = pixel & 0x1F;

				uint8_t bgr[3] = {
					(b5 << 3) | (b5 >> 2),
					(g6 << 2) | (g6 >> 4),
					(r5 << 3) | (r5 >> 2)
				};
				fwrite(bgr, 1, 3, fp);
			}
		}

		if (padding > 0) {
			uint8_t pad[3] = { 0, 0, 0 };
			fwrite(pad, 1, padding, fp);
		}
	}

	ret = ferror(fp) ? -1 : 0;
	fclose(fp);
	return ret;
}

static void usage(const char *prog, int fd) {
	drmModeCrtcPtr crtc;
	drmModeResPtr res;
	int i;

	res = drmModeGetResources(fd);

	fprintf(stderr, "Usage:\n");
	fprintf(stderr, "  %s [options] [--crtc|--connector|--plane|--fb] OBJ_ID\n", prog);
	fprintf(stderr, "\nOptions:\n");
	fprintf(stderr, "  -o <file>   Output BMP file (default: " DEFAULT_OUTPUT ")\n");
	fprintf(stderr, "\nExamples:\n");
	fprintf(stderr, "  %s                         # auto-detect, save to " DEFAULT_OUTPUT "\n", prog);
	fprintf(stderr, "  %s -o screen.bmp           # save as screen.bmp\n", prog);
	fprintf(stderr, "  %s --fb 42 > out.raw       # dump raw to stdout\n", prog);
	fprintf(stderr, "\nValid crtcs:");
	for (i = 0; i < res->count_crtcs; i++) {
		crtc = drmModeGetCrtc(fd, res->crtcs[i]);
		if (crtc && crtc->mode_valid)
			fprintf(stderr, " %d", crtc->crtc_id);
		drmModeFreeCrtc(crtc);
	}
	fprintf(stderr, "\n");

	drmModeFreeResources(res);
	exit(-1);
}

int main(int argc, const char **argv) {
	int fd, fb_id;
	struct fb_info info;
	const char *output = DEFAULT_OUTPUT;
	int raw_output = 0;
	int arg_start = 1;

	memset(&info, 0, sizeof(info));

	fd = drmOpen("rockchip", NULL);
	if (fd < 0) {
		fprintf(stderr, "drmOpen failed: %s\n", strerror(errno));
		return -1;
	}
	fcntl(fd, F_SETFD, FD_CLOEXEC);

	while (arg_start < argc && argv[arg_start][0] == '-') {
		if (!strcmp(argv[arg_start], "-o")) {
			if (arg_start + 1 >= argc) {
				fprintf(stderr, "Missing filename for -o\n");
				usage(argv[0], fd);
			}
			output = argv[++arg_start];
		} else if (!strcmp(argv[arg_start], "--raw")) {
			raw_output = 1;
		} else {
			break;
		}
		arg_start++;
	}

	{
		int remaining = argc - arg_start;

		switch (remaining) {
		case 2:
			fb_id = atoi(argv[arg_start + 1]);
			if (fb_id <= 0)
				usage(argv[0], fd);

			if (!strcmp(argv[arg_start], "--crtc"))
				fb_id = get_crtc_fb(fd, fb_id, &info);
			else if (!strcmp(argv[arg_start], "--connector"))
				fb_id = get_connector_fb(fd, fb_id, &info);
			else if (!strcmp(argv[arg_start], "--plane"))
				fb_id = get_plane_fb(fd, fb_id, &info);
			else if (strcmp(argv[arg_start], "--fb"))
				usage(argv[0], fd);

			break;
		case 1:
			fb_id = atoi(argv[arg_start]);
			if (fb_id <= 0)
				usage(argv[0], fd);
			break;
		default:
			fb_id = get_default_fb(fd, &info);
		}
	}

	if (fb_id <= 0) {
		fprintf(stderr, "Failed to get framebuffer id\n");
		drmClose(fd);
		return -1;
	}

	if (get_fb_info(fd, fb_id, &info)) {
		drmClose(fd);
		return -1;
	}

	fprintf(stderr, "FB %d: %ux%u, pitch=%u, bpp=%u, format=0x%x\n",
		fb_id, info.width, info.height, info.pitch,
		info.bpp, info.drm_format);

	size_t size = (size_t)info.pitch * info.height;

	int prime_fd = -1;
	void *ptr = map_fb(fd, info.handle, size, &prime_fd);
	if (!ptr) {
		drmClose(fd);
		return -1;
	}

	int ret;
	if (raw_output) {
		ret = (write(1, ptr, size) == (ssize_t)size) ? 0 : -1;
		if (ret)
			fprintf(stderr, "write failed: %s\n", strerror(errno));
	} else {
		ret = save_bmp(output, ptr, &info);
		if (ret == 0)
			fprintf(stderr, "Saved %s (%ux%u, %u bpp)\n",
				output, info.width, info.height, info.bpp);
	}

	munmap(ptr, size);
	if (prime_fd >= 0)
		close(prime_fd);
	if (info.handle_from_getfb)
		destroy_dumb(fd, info.handle);
	drmClose(fd);

	return ret;
}
