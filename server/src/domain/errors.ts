export class DomainError extends Error {
  readonly code: string
  readonly status: number

  constructor(code: string, message: string, status = 400) {
    super(message)
    this.name = 'DomainError'
    this.code = code
    this.status = status
  }
}

export function notFound(message: string): DomainError {
  return new DomainError('not_found', message, 404)
}

export function invalid(message: string): DomainError {
  return new DomainError('invalid_argument', message, 400)
}

export function forbidden(message: string): DomainError {
  return new DomainError('forbidden', message, 403)
}
