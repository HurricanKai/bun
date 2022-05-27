/*
    This file is part of the WebKit open source project.
    This file has been generated by generate-bindings.pl. DO NOT MODIFY!

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.

    You should have received a copy of the GNU Library General Public License
    along with this library; see the file COPYING.LIB.  If not, write to
    the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
    Boston, MA 02110-1301, USA.
*/

#include "config.h"
#include "JSReadableStream.h"

#include "ExtendedDOMClientIsoSubspaces.h"
#include "ExtendedDOMIsoSubspaces.h"
#include "JSDOMAttribute.h"
#include "JSDOMBinding.h"
#include "JSDOMBuiltinConstructor.h"
#include "JSDOMExceptionHandling.h"
#include "JSDOMGlobalObjectInlines.h"
#include "JSDOMOperation.h"
#include "JSDOMWrapperCache.h"
#include "ReadableStreamBuiltins.h"
#include "WebCoreJSClientData.h"
#include <JavaScriptCore/FunctionPrototype.h>
#include <JavaScriptCore/JSCInlines.h>
#include <JavaScriptCore/JSDestructibleObjectHeapCellType.h>
#include <JavaScriptCore/SlotVisitorMacros.h>
#include <JavaScriptCore/SubspaceInlines.h>
#include <wtf/GetPtr.h>
#include <wtf/PointerPreparations.h>

namespace WebCore {
using namespace JSC;

// Functions

// Attributes

static JSC_DECLARE_CUSTOM_GETTER(jsReadableStreamConstructor);

class JSReadableStreamPrototype final : public JSC::JSNonFinalObject {
public:
    using Base = JSC::JSNonFinalObject;
    static JSReadableStreamPrototype* create(JSC::VM& vm, JSDOMGlobalObject* globalObject, JSC::Structure* structure)
    {
        JSReadableStreamPrototype* ptr = new (NotNull, JSC::allocateCell<JSReadableStreamPrototype>(vm)) JSReadableStreamPrototype(vm, globalObject, structure);
        ptr->finishCreation(vm);
        return ptr;
    }

    DECLARE_INFO;
    template<typename CellType, JSC::SubspaceAccess>
    static JSC::GCClient::IsoSubspace* subspaceFor(JSC::VM& vm)
    {
        STATIC_ASSERT_ISO_SUBSPACE_SHARABLE(JSReadableStreamPrototype, Base);
        return &vm.plainObjectSpace();
    }
    static JSC::Structure* createStructure(JSC::VM& vm, JSC::JSGlobalObject* globalObject, JSC::JSValue prototype)
    {
        return JSC::Structure::create(vm, globalObject, prototype, JSC::TypeInfo(JSC::ObjectType, StructureFlags), info());
    }

private:
    JSReadableStreamPrototype(JSC::VM& vm, JSC::JSGlobalObject*, JSC::Structure* structure)
        : JSC::JSNonFinalObject(vm, structure)
    {
    }

    void finishCreation(JSC::VM&);
};
STATIC_ASSERT_ISO_SUBSPACE_SHARABLE(JSReadableStreamPrototype, JSReadableStreamPrototype::Base);

using JSReadableStreamDOMConstructor = JSDOMBuiltinConstructor<JSReadableStream>;

template<> const ClassInfo JSReadableStreamDOMConstructor::s_info = { "ReadableStream"_s, &Base::s_info, nullptr, nullptr, CREATE_METHOD_TABLE(JSReadableStreamDOMConstructor) };

template<> JSValue JSReadableStreamDOMConstructor::prototypeForStructure(JSC::VM& vm, const JSDOMGlobalObject& globalObject)
{
    UNUSED_PARAM(vm);
    return globalObject.functionPrototype();
}

template<> void JSReadableStreamDOMConstructor::initializeProperties(VM& vm, JSDOMGlobalObject& globalObject)
{
    putDirect(vm, vm.propertyNames->length, jsNumber(0), JSC::PropertyAttribute::ReadOnly | JSC::PropertyAttribute::DontEnum);
    JSString* nameString = jsNontrivialString(vm, "ReadableStream"_s);
    m_originalName.set(vm, this, nameString);
    putDirect(vm, vm.propertyNames->name, nameString, JSC::PropertyAttribute::ReadOnly | JSC::PropertyAttribute::DontEnum);
    putDirect(vm, vm.propertyNames->prototype, JSReadableStream::prototype(vm, globalObject), JSC::PropertyAttribute::ReadOnly | JSC::PropertyAttribute::DontEnum | JSC::PropertyAttribute::DontDelete);
}

template<> FunctionExecutable* JSReadableStreamDOMConstructor::initializeExecutable(VM& vm)
{
    return readableStreamInitializeReadableStreamCodeGenerator(vm);
}

/* Hash table for prototype */

static const HashTableValue JSReadableStreamPrototypeTableValues[] = {
    { "constructor"_s, static_cast<unsigned>(JSC::PropertyAttribute::DontEnum), NoIntrinsic, { (intptr_t) static_cast<PropertySlot::GetValueFunc>(jsReadableStreamConstructor), (intptr_t) static_cast<PutPropertySlot::PutValueFunc>(0) } },
    { "locked"_s, static_cast<unsigned>(JSC::PropertyAttribute::DontEnum | JSC::PropertyAttribute::ReadOnly | JSC::PropertyAttribute::Accessor | JSC::PropertyAttribute::Builtin), NoIntrinsic, { (intptr_t) static_cast<BuiltinGenerator>(readableStreamLockedCodeGenerator), (intptr_t)(0) } },
    { "cancel"_s, static_cast<unsigned>(JSC::PropertyAttribute::DontEnum | JSC::PropertyAttribute::Builtin), NoIntrinsic, { (intptr_t) static_cast<BuiltinGenerator>(readableStreamCancelCodeGenerator), (intptr_t)(0) } },
    { "getReader"_s, static_cast<unsigned>(JSC::PropertyAttribute::DontEnum | JSC::PropertyAttribute::Builtin), NoIntrinsic, { (intptr_t) static_cast<BuiltinGenerator>(readableStreamGetReaderCodeGenerator), (intptr_t)(0) } },
    { "pipeTo"_s, static_cast<unsigned>(JSC::PropertyAttribute::DontEnum | JSC::PropertyAttribute::Builtin), NoIntrinsic, { (intptr_t) static_cast<BuiltinGenerator>(readableStreamPipeToCodeGenerator), (intptr_t)(1) } },
    { "pipeThrough"_s, static_cast<unsigned>(JSC::PropertyAttribute::DontEnum | JSC::PropertyAttribute::Builtin), NoIntrinsic, { (intptr_t) static_cast<BuiltinGenerator>(readableStreamPipeThroughCodeGenerator), (intptr_t)(2) } },
    { "tee"_s, static_cast<unsigned>(JSC::PropertyAttribute::DontEnum | JSC::PropertyAttribute::Builtin), NoIntrinsic, { (intptr_t) static_cast<BuiltinGenerator>(readableStreamTeeCodeGenerator), (intptr_t)(0) } },
};

const ClassInfo JSReadableStreamPrototype::s_info = { "ReadableStream"_s, &Base::s_info, nullptr, nullptr, CREATE_METHOD_TABLE(JSReadableStreamPrototype) };

void JSReadableStreamPrototype::finishCreation(VM& vm)
{
    Base::finishCreation(vm);
    auto clientData = WebCore::clientData(vm);
    this->putDirect(vm, clientData->builtinNames().bunNativePtrPrivateName(), jsNumber(0), JSC::PropertyAttribute::ReadOnly | JSC::PropertyAttribute::DontEnum | JSC::PropertyAttribute::DontDelete | 0);
    reifyStaticProperties(vm, JSReadableStream::info(), JSReadableStreamPrototypeTableValues, *this);
    JSC_TO_STRING_TAG_WITHOUT_TRANSITION();
}

const ClassInfo JSReadableStream::s_info = { "ReadableStream"_s, &Base::s_info, nullptr, nullptr, CREATE_METHOD_TABLE(JSReadableStream) };

JSReadableStream::JSReadableStream(Structure* structure, JSDOMGlobalObject& globalObject)
    : JSDOMObject(structure, globalObject)
{
}

void JSReadableStream::finishCreation(VM& vm)
{
    Base::finishCreation(vm);
    ASSERT(inherits(info()));
}

JSObject* JSReadableStream::createPrototype(VM& vm, JSDOMGlobalObject& globalObject)
{
    return JSReadableStreamPrototype::create(vm, &globalObject, JSReadableStreamPrototype::createStructure(vm, &globalObject, globalObject.objectPrototype()));
}

JSObject* JSReadableStream::prototype(VM& vm, JSDOMGlobalObject& globalObject)
{
    return getDOMPrototype<JSReadableStream>(vm, globalObject);
}

JSValue JSReadableStream::getConstructor(VM& vm, const JSGlobalObject* globalObject)
{
    return getDOMConstructor<JSReadableStreamDOMConstructor, DOMConstructorID::ReadableStream>(vm, *jsCast<const JSDOMGlobalObject*>(globalObject));
}

void JSReadableStream::destroy(JSC::JSCell* cell)
{
    JSReadableStream* thisObject = static_cast<JSReadableStream*>(cell);
    thisObject->JSReadableStream::~JSReadableStream();
}

JSC_DEFINE_CUSTOM_GETTER(jsReadableStreamConstructor, (JSGlobalObject * lexicalGlobalObject, EncodedJSValue thisValue, PropertyName))
{
    VM& vm = JSC::getVM(lexicalGlobalObject);
    auto throwScope = DECLARE_THROW_SCOPE(vm);
    auto* prototype = jsDynamicCast<JSReadableStreamPrototype*>(JSValue::decode(thisValue));
    if (UNLIKELY(!prototype))
        return throwVMTypeError(lexicalGlobalObject, throwScope);
    return JSValue::encode(JSReadableStream::getConstructor(JSC::getVM(lexicalGlobalObject), prototype->globalObject()));
}

JSC::GCClient::IsoSubspace* JSReadableStream::subspaceForImpl(JSC::VM& vm)
{
    return WebCore::subspaceForImpl<JSReadableStream, UseCustomHeapCellType::No>(
        vm,
        [](auto& spaces) { return spaces.m_clientSubspaceForReadableStream.get(); },
        [](auto& spaces, auto&& space) { spaces.m_clientSubspaceForReadableStream = WTFMove(space); },
        [](auto& spaces) { return spaces.m_subspaceForReadableStream.get(); },
        [](auto& spaces, auto&& space) { spaces.m_subspaceForReadableStream = WTFMove(space); });
}

}
