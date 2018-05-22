1.支持在文件的其他地方缓存function的热更
例如 A.lua
	local B = require "B"
	local A = {}
	A.f = B.f
	return A

	B.lua
	local B = {}
	function B.f()
	end
	return B
这种情况可以正确更新A.f

2.支持upvalue的自动查找
	例如A.lua
		local a, b
		function A()
			return a
		end
		function B()
			return b
		end
	如果将function A() 改为 return a,b
	会自动把A和B的upvalue都对应上

3.不支持用function作为key(这种function不会被热更新)

4.支持table的嵌套
	local c = {}
	local a = 1
	function c.F()
		return a
	end
	c.__NeedReload = true
	function A()
		return c
	end
	这种情况下,c是A的upvalue,a是c.F的upvalue，一般是遍历不到c.F从而导致upvalue a的丢失
	如果定义了c.__NeedReload,此时热更的时候会遍历c

5.支持部分更新
	可以仅仅更新指定package的部分函数
	例如Reloader.MyReload("Test",[[
		local Test = {}
		local b
		function Test.A()
			return b
		end
		return Test
	]])
	这种情况下为了能对应upvalue b的值,要么A原本就是Test里面的一个函数
	要么需要多加几个函数来辅助判断upvalue b到底需要映射到哪个upvalue
	当然如果Test这个文件里面名字为b的upvalue只有一个,那就不需要上面的限制条件了