/*-
 *   BSD LICENSE
 *
 *   Copyright (c) Intel Corporation.
 *   All rights reserved.
 *
 *   Redistribution and use in source and binary forms, with or without
 *   modification, are permitted provided that the following conditions
 *   are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in
 *       the documentation and/or other materials provided with the
 *       distribution.
 *     * Neither the name of Intel Corporation nor the names of its
 *       contributors may be used to endorse or promote products derived
 *       from this software without specific prior written permission.
 *
 *   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 *   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef SPDK_INTERNAL_ACCEL_ENGINE_H
#define SPDK_INTERNAL_ACCEL_ENGINE_H

#include "spdk/stdinc.h"

#include "spdk/accel_engine.h"
#include "spdk/queue.h"
#include "spdk/config.h"

#ifdef SPDK_CONFIG_ISAL
#include "../isa-l/include/igzip_lib.h"
#endif

struct spdk_accel_task;

void spdk_accel_task_complete(struct spdk_accel_task *task, int status);

struct accel_io_channel {
	struct spdk_io_channel		*engine_ch[ACCEL_OPC_LAST];
	/* for ISAL */
#ifdef SPDK_CONFIG_ISAL
	struct isal_zstream		stream;
	struct inflate_state		state;
#endif
	void				*task_pool_base;
	TAILQ_HEAD(, spdk_accel_task)	task_pool;
};

struct sw_accel_io_channel {
	struct spdk_poller		*completion_poller;
	TAILQ_HEAD(, spdk_accel_task)	tasks_to_complete;
};

struct spdk_accel_task {
	struct accel_io_channel		*accel_ch;
	spdk_accel_completion_cb	cb_fn;
	void				*cb_arg;
	union {
		struct {
			struct iovec		*iovs; /* iovs passed by the caller */
			uint32_t		iovcnt; /* iovcnt passed by the caller */
		} v;
		void				*src;
	};
	union {
		void			*dst;
		void			*src2;
	};
	union {
		void				*dst2;
		uint32_t			seed;
		uint64_t			fill_pattern;
	};
	union {
		uint32_t		*crc_dst;
		uint32_t		*output_size;
	};
	enum accel_opcode		op_code;
	uint64_t			nbytes;
	uint64_t			nbytes_dst;
	int				flags;
	int				status;
	TAILQ_ENTRY(spdk_accel_task)	link;
};

struct spdk_accel_engine {
	const char *name;
	bool (*supports_opcode)(enum accel_opcode);
	struct spdk_io_channel *(*get_io_channel)(void);
	int (*submit_tasks)(struct spdk_io_channel *ch, struct spdk_accel_task *accel_task);
	TAILQ_ENTRY(spdk_accel_engine) tailq;
};

struct spdk_accel_module_if {
	/** Initialization function for the module.  Called by the spdk
	 *   application during startup.
	 *
	 *  Modules are required to define this function.
	 */
	int	(*module_init)(void);

	/** Finish function for the module.  Called by the spdk application
	 *   before the spdk application exits to perform any necessary cleanup.
	 *
	 *  Modules are not required to define this function.
	 */
	void	(*module_fini)(void *ctx);

	/**
	 * Write Acceleration module configuration into provided JSON context.
	 */
	void	(*write_config_json)(struct spdk_json_write_ctx *w);

	/**
	 * Returns the allocation size required for the modules to use for context.
	 */
	size_t	(*get_ctx_size)(void);

	TAILQ_ENTRY(spdk_accel_module_if)	tailq;
};

void spdk_accel_engine_register(struct spdk_accel_engine *accel_engine);
void spdk_accel_module_list_add(struct spdk_accel_module_if *accel_module);

#define SPDK_ACCEL_MODULE_REGISTER(init_fn, fini_fn, config_json, ctx_size_fn)				\
	static struct spdk_accel_module_if init_fn ## _if = {						\
	.module_init		= init_fn,								\
	.module_fini		= fini_fn,								\
	.write_config_json	= config_json,								\
	.get_ctx_size		= ctx_size_fn,								\
	};												\
	__attribute__((constructor)) static void init_fn ## _init(void)					\
	{												\
		spdk_accel_module_list_add(&init_fn ## _if);						\
	}

#endif
