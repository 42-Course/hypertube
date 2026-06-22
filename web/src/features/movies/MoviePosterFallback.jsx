function MoviePosterFallback({ title, className = '' }) {
  return (
    <div
      className={`flex h-full w-full items-center justify-center overflow-hidden bg-[radial-gradient(circle_at_top,_rgba(239,68,68,0.28),_rgba(24,24,27,0.95)_46%,_#09090b_100%)] px-5 text-center ${className}`}
    >
      <div className="relative z-10">
        <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl border border-red-400/30 bg-red-500/10 text-2xl text-red-100 shadow-[0_0_50px_rgba(239,68,68,0.25)]">
          🎬
        </div>
        <p className="mt-4 line-clamp-3 text-sm font-semibold leading-5 text-zinc-100">
          {title}
        </p>
      </div>
    </div>
  )
}

export default MoviePosterFallback
