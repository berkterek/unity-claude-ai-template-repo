using System;
using UnityEngine;
using VContainer;
using VContainer.Unity;

namespace Fixtures.MembersDocs
{
    public interface IFoo
    {
    }

    public interface IThing
    {
    }

    public sealed class A : IInitializable
    {
        public void Initialize()
        {
        }
    }

    public sealed class B : IInitializable
    {
        public void Initialize()
        {
        }
    }

    public sealed class C : IFoo, IDisposable
    {
        public void Dispose()
        {
        }
    }

    public sealed class Thing : IThing
    {
    }

    public sealed class D : MonoBehaviour
    {
    }

    public static class RegistrationsModule
    {
        public static void Install(IContainerBuilder builder)
        {
            builder.RegisterEntryPoint<A>(Lifetime.Singleton).AsImplementedInterfaces();
            builder.RegisterEntryPoint<B>(Lifetime.Singleton).AsSelf();
            builder.Register<C>(Lifetime.Singleton).As<IFoo>().AsImplementedInterfaces();
            builder.RegisterFactory<IThing>(r => () => new Thing());
            builder.RegisterComponentInHierarchy<D>();
        }
    }
}
