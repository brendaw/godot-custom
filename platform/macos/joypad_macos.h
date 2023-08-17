/**************************************************************************/
/*  joypad_macos.h                                                        */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "core/input/input.h"
#import <CoreHaptics/CoreHaptics.h>
#import <GameController/GameController.h>

@interface JoypadMacOSObserver : NSObject

- (void)startObserving;
- (void)startProcessing;
- (void)finishObserving;

@end

@interface Joypad : NSObject

@property(assign, nonatomic) BOOL force_feedback;
@property(assign, nonatomic) NSInteger ff_effect_timestamp;
@property(strong, nonatomic) GCController *controller;
@property(strong, nonatomic) CHHapticEngine *motion_engine;
@property(strong, nonatomic) id<CHHapticPatternPlayer> pattern_player;

- (instancetype)init;
- (instancetype)init:(GCController *)controller;

@end

class JoypadMacOS {
private:
	JoypadMacOSObserver *observer;

public:
	JoypadMacOS();
	~JoypadMacOS();

	void joypad_vibration_start(Joypad *p_joypad, float p_weak_magnitude, float p_strong_magnitude, float p_duration, uint64_t p_timestamp);
	void joypad_vibration_stop(Joypad *p_joypad, uint64_t p_timestamp);

	void start_processing();
	void process_joypads();
};
